# Show-Control Architecture

**Status of this document:** canonical for *direction*, PROPOSED for *content*.
Established on branch `docs/lighting-audio-show-control-architecture` against
HEAD `bc91b77`.

**Nothing described in Part 2 or later is implemented.** This document describes
how Lights would evolve into a synchronized show-control system. It is an
architecture reference and a future implementation specification, not a
description of the running application. Evidence labels are defined in
[project_overview.md](project_overview.md) and are used here exactly as they are
used elsewhere in this set.

For what Lights does *today*, read [project_overview.md](project_overview.md)
and [architecture.md](architecture.md) first. This document assumes both.

## Companion documents

| Document | Covers |
| --- | --- |
| [audio_reactivity_architecture.md](audio_reactivity_architecture.md) | Audio decoding, analysis, the feature timeline, and cue-mapping strategy |
| [fixture_and_transport_strategy.md](fixture_and_transport_strategy.md) | Fixture definitions, capabilities, rendering, and the WLED/DMX transports |
| [laser_and_haze_safety.md](laser_and_haze_safety.md) | Safety policy for laser and haze output — **read before any laser or haze work** |
| [show_control_recommendations.md](show_control_recommendations.md) | Every recommended library and tool, with rationale, prerequisites, risks, and impact |
| [show_control_roadmap.md](show_control_roadmap.md) | Phases 1–5, and how they map onto the existing M0–M12 milestones |
| [decisions.md](decisions.md) | Proposed decisions PD-1…PD-12 arising from this document |

---

# Part 1 — What Lights is today, in show-control terms

## VERIFIED CURRENT BEHAVIOR

This part exists so the rest of the document cannot be misread as a description
of current capability. Each row was re-checked against HEAD `bc91b77`.

Lights is **not** a generic smart-home lighting application, and it is also not
yet a show-control system. It is a single-operator, single-rig, single-universe
DMX controller with an onset-triggered preset cycler and a nonphysical ILDA
sequencer.

### The current subsystem boundaries

| Boundary | Where it lives | What it actually does |
| --- | --- | --- |
| User interface | `frontend/` — vanilla JS, no build step, served by the `StaticFiles` mount at `/` | Pages for presets, device presets, scenes, full scenes, ILDA, and active show. Fixture knowledge is hardcoded here as well as in the backend. |
| WLED control | **No direct WLED code exists.** | WLED is reached only indirectly, by asking LedFx to activate a scene by name. There is no WLED JSON API client, no WebSocket client, and no realtime pixel transport in this repository. |
| LedFx integration | `backend/ledfx/client.py` (63 lines) | `GET /api/scenes`, and `PUT /api/scenes` with `{"id":…, "action":"activate"}`. Host is `config.server_host`, port hardcoded to 8888 (F17). |
| DMX control | `backend/dmx/sender.py`, `frame.py`, `mapper.py` | One sACN universe, unicast to `config.IP`, 512 channels. `MAPPER` concatenates each device's `active_channels` in `order` sequence. |
| Audio handling | `frontend/js/home.js` only | Browser microphone → `AnalyserNode` (fftSize 2048) → spectral-flux onset detection over FFT bins 2–6 → `POST /api/active-scene/advance`. |
| Configuration | `backend/models/config.py`, `backend/paths.py` | A single `CONFIG` JSON object; data directory resolved from `LIGHTSAPP_DATA_DIR` or a per-OS default. |
| Device models | `backend/models/` — Pydantic | `DMXDevice(id, order, channels, active_channels, control_type)`. No manufacturer, model, mode, universe, or start address. |
| Persistence | `backend/models/storage.py` (43 lines) | `json.dump` into the destination opened `"w"`. Non-atomic (F7); read failures collapse to `[]`/`None` (F8). |
| Networking | `sacn` (UDP out), `requests` (LedFx), Uvicorn (bind) | No authentication on any route (F12); CORS wildcarded (F13). |
| Testing | `backend/ilda/test_reader.py` | A CLI smoke script. There is no pytest suite (F10). |

### The five facts that most constrain this architecture

1. **There is no audio-file path anywhere in the repository.** Audio exists only
   as a live microphone stream inside the browser. Decoding, analysis, caching,
   and any notion of a timeline are entirely absent. This is the single largest
   gap between current state and the target.

2. **The current "beat" signal is an onset trigger, not a clock.** VERIFIED
   CURRENT BEHAVIOR: `frontend/js/home.js:104-160` computes spectral flux over
   FFT bins 2–6, compares it to a rolling mean plus a standard-deviation
   multiplier, requires a rising edge and an 80 ms cooldown, and fires an HTTP
   POST. There is no tempo estimate, no downbeat, no phase, no section
   detection, and no confidence value. Sensitivity is a hardcoded constant
   (`SENSITIVITY = 25`, `home.js:18`). Show time does not exist as a concept.

3. **DMX addressing is implicit and positional.** CODE-INSPECTED ONLY:
   `backend/dmx/mapper.py:6-10` sorts devices by `order` and concatenates
   `active_channels`. A fixture's DMX start address is therefore the cumulative
   length of every preceding device's `active_channels` list. Nothing enforces
   `len(active_channels) == channels` (F11), so a single wrong-length list
   silently shifts the address of every downstream fixture. There are no
   addresses to validate for collisions today, because there are no addresses —
   only positions.

4. **Only one universe is ever activated.** VERIFIED CURRENT BEHAVIOR:
   `backend/dmx/sender.py:59` calls `activate_output(self.universe)` once, for
   `config.universe`. Multi-universe output does not exist.

5. **Persistence is the control bus.** F6. The API writes `devices.json` and the
   send thread polls it. Any show engine built on top of the current design
   would inherit disk latency in its output path. This must be fixed (M5) before
   synchronization work is meaningful.

---

# Part 2 — Project vision

## DESIGN INTENT and TARGET ARCHITECTURE

Lights is intended to become a **synchronized lighting and effects controller**
for one operator running one rig to recorded music. It coordinates:

- WLED pixel devices (strips and matrices);
- DMX fixtures generally, addressed and patched rather than positionally
  concatenated;
- RGB/RGBW PARs;
- DMX light bars;
- Keobin fixtures;
- Chauvet GigBAR-family multi-effect fixtures;
- DMX lasers, under the safety policy in
  [laser_and_haze_safety.md](laser_and_haze_safety.md);
- DMX haze, under the same document's duty-cycle policy;
- **complete audio files supplied directly to the application**, analyzed
  offline;
- shows that are both automatically generated and manually authored.

It remains a single-operator tool for a known rig. It is not a lighting console,
not a venue management system, and not a smart-home product. Where a
general-purpose console would add flexibility, Lights should prefer determinism
and a short path from "here is the track" to "here is the show".

## Target execution flow

```text
Audio file
    ↓
Audio decoding and normalization          ← one canonical PCM boundary
    ↓
Feature extraction                        ← versioned, deterministic
    ↓
Time-aligned audio feature timeline       ← cached by content hash
    ↓
Show generation                           ← style + fixture groups + overrides
    ↓
Semantic cue timeline                     ← NO DMX channel numbers here
    ↓
Fixture rendering                         ← capability → channel translation
    ↓
WLED and DMX transports                   ← real · null · recording
    ↓
Physical devices
```

Two properties of this flow matter more than any individual stage.

**The pipeline is cut in half at the semantic cue timeline.** Everything above
it knows about music and nothing about DMX. Everything below it knows about
fixtures and nothing about music. This is the boundary that makes one analysis
reusable across rigs, and one rig reusable across tracks. PD-1 records it as a
proposed binding decision.

**Every stage above "Fixture rendering" is deterministic and hardware-free.**
Given the same audio file, the same extractor version, and the same generation
configuration, the show is byte-identical — and can be produced, tested, and
diffed on WSL2 with no rig present. Only the last two stages need hardware, and
both have null and recording implementations. This is what makes the whole
system testable under the constraints in
[platform_support.md](platform_support.md).

---

# Part 3 — Recommended architecture

## TARGET ARCHITECTURE

Six layers, each with a single responsibility and an explicit interface to the
next. The layer boundaries are the deliverable; the specific libraries behind
them are replaceable and are argued separately in
[show_control_recommendations.md](show_control_recommendations.md).

```text
┌───────────────────────────────────────────────────────────────────────┐
│  AUDIO ANALYSIS LAYER                        offline · deterministic  │
│  decode → normalize → extract → confidence → cache                    │
│  output: AudioFeatureTimeline (versioned artifact, keyed by hash)     │
└───────────────────────────────┬───────────────────────────────────────┘
                                │  knows: music.  knows nothing of fixtures.
┌───────────────────────────────▼───────────────────────────────────────┐
│  SHOW-GENERATION LAYER                       offline · deterministic  │
│  style + fixture groups + intensity profile + manual edits            │
│  conflict resolution by cue priority                                  │
│  output: ShowTimeline of semantic Cues                                │
└───────────────────────────────┬───────────────────────────────────────┘
                                │  ═══ THE SEMANTIC BOUNDARY (PD-1) ═══
                                │  no channel numbers cross this line
┌───────────────────────────────▼───────────────────────────────────────┐
│  FIXTURE-DEFINITION LAYER                    data · validated · fails closed │
│  manufacturer · model · mode · channels · capabilities                │
│  instances: universe · start address · groups                         │
│  validation: address collision · universe bounds · unknown mode       │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
┌───────────────────────────────▼───────────────────────────────────────┐
│  RENDERING LAYER                             pure functions           │
│  semantic action + fixture mode → channel values / WLED state / pixels│
│  renderers reusable BY CAPABILITY, not by fixture name                │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
┌───────────────────────────────▼───────────────────────────────────────┐
│  TRANSPORT LAYER                             real · null · recording  │
│  WledJsonTransport · WledRealtimeTransport · DmxTransport             │
│  blackout · safe shutdown · latency compensation hooks                │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
┌───────────────────────────────▼───────────────────────────────────────┐
│  TIMELINE AND SYNCHRONIZATION LAYER          the only owner of TIME   │
│  monotonic clock · playback position · lookahead scheduling           │
│  per-device latency offsets · fixed-rate DMX · drift correction       │
└───────────────────────────────────────────────────────────────────────┘
```

The synchronization layer is drawn last but is not "lowest" — it drives the
render-and-transmit cycle and pulls from the show timeline. It is placed at the
bottom because it is the only component permitted to read a clock.

## 3.1 Audio analysis layer

**Responsibilities.** Decode common audio formats. Normalize sample rate,
channel count, and sample representation to one canonical signal. Detect beats,
downbeats, onsets, energy, frequency-band energy, tempo, sections, and silence.
Assign a confidence value to every detected event class. Cache results keyed by
audio-file hash. Produce a deterministic `AudioFeatureTimeline`.

**Explicitly not its responsibility.** Anything about lighting. This layer must
never import a fixture, transport, or cue type.

**Repository fit.** This layer is entirely new. The nearest existing thing is
`frontend/js/home.js`, which is realtime, browser-side, and produces a single
untyped trigger. It is not a precursor — it is a different mechanism for a
different purpose, and PD-6 proposes keeping it as the live-performance fallback
rather than replacing it.

One artifact from the deleted AI system is worth noting because it will be
misread otherwise: `backend/models/ai_mode_state.py:42-58` defines
`AudioFeaturesRequest` with `frequency_bands`, `beat_features`,
`spectral_centroid`, and `energy`. That model is orphaned (its routes fail to
import, F20), it is a *realtime, per-tick* request shape, and it is **not** a
timeline. It should not be reused as the artifact schema, though the choice of
features it lists is reasonable evidence of what the creator wanted.

## 3.2 Show-generation layer

**Responsibilities.** Convert an `AudioFeatureTimeline` into semantic lighting
cues. Support generated cues and manually authored or edited cues in the same
timeline. Resolve conflicts by cue priority. Regenerate deterministically.
Support styles, intensity profiles, and fixture groups.

**The rule that gives this layer its value:** a cue says *what should happen*,
never *which channel*. `Cue(action="strobe", target=group("bars"), …)` is
correct. `Cue(channel=14, value=255)` is a layering violation and must fail
review.

**Repository fit.** Lights already has a curated-scene model — device preset →
combined preset → scene → full scene — and that model is its most valuable
asset (D-1). The show generator should **target the existing scene vocabulary
first**, emitting cues that select and modulate existing presets and scenes,
before it attempts to author fixture actions from nothing. This keeps the
operator's curation in the loop and makes the first generator far smaller.

## 3.3 Fixture-definition layer

**Responsibilities.** Define manufacturers, models, modes, channels, and
capabilities as *data*. Represent WLED devices and DMX fixtures under one
consistent instance model. Support instances with base addresses, universes,
and group membership. Validate address collisions and universe boundaries.
**Fail closed for unknown fixture modes.**

**Repository fit.** This directly supersedes F19. Today, fixture knowledge is
hardcoded in `backend/routes/data.py:57-125` (bootstrapping `gigbar`, `keobin`,
`haze` with fixed channel counts) and in `frontend/js/device_presets.js`, which
carries a `MODE_VALUES` table mapping named modes to channel numbers for
`gigbar` sub-devices (`par_1`, `par_2`, `derby_1`, `derby_2`, `laser`, `strobe`)
and `keobin` sub-devices (four lasers, a magic ball, a strobe block).

That table is the repository's only existing fixture-profile data, and it is the
natural migration source for M10. It is also **unverified against any
manufacturer manual**, which is why
[fixture_and_transport_strategy.md](fixture_and_transport_strategy.md) requires
manual-based re-derivation rather than a mechanical copy.

## 3.4 Rendering layer

**Responsibilities.** Translate semantic cue actions into WLED state changes,
WLED realtime pixel frames, and DMX channel values. Isolate fixture-specific
behavior. Make renderers reusable by capability.

A renderer is a pure function. Given a capability, a value, and a fixture mode,
it returns channel assignments. It reads no clock, opens no socket, and touches
no disk. This is what makes fixture conformance testing (golden channel frames)
possible at all.

## 3.5 Transport layer

**Responsibilities.** Send WLED JSON, WLED WebSocket, and WLED realtime
UDP/DDP output. Send DMX via Art-Net, sACN, or an OLA-backed adapter. Provide
mock and recording transports. Support blackout and safe shutdown. Expose
latency-compensation configuration.

**Do not force one interface across all of them.** This repeats a constraint
already recorded in [architecture.md](architecture.md) Part 3, and it matters
more here, not less: WLED state control, WLED pixel streaming, and DMX universe
transmission have genuinely different shapes — request/response, continuous
frame stream, and fixed-rate universe frame respectively. Share only the
lifecycle concepts that are actually shared: `open`, `close`, `blackout`,
`is_connected`, and a latency offset.

**Repository fit.** The one existing precursor is
`backend/ilda/sink.py` — `PointSink` / `NullSink` / `LoggingSink`. That is
exactly the shape wanted, and it should be the pattern the DMX and WLED
transports copy. DMX and LedFx currently have no injectable seam at all, which
is M2's job.

## 3.6 Timeline and synchronization layer

**Responsibilities.** Own a monotonic high-resolution clock. Make audio playback
position the authoritative show time. Schedule with lookahead rather than
reacting at the timestamp. Compensate per-device latency. Run WLED and DMX at
their own appropriate rates. Detect and correct drift.

```text
                     ┌──────────────────────────────┐
                     │  PLAYBACK CLOCK (monotonic)  │
                     │  show_time = audio position  │
                     └───────────────┬──────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
     ┌────────▼────────┐   ┌─────────▼─────────┐  ┌─────────▼─────────┐
     │ LOOKAHEAD       │   │ DMX RENDER TICK   │  │ WLED PIXEL TICK   │
     │ SCHEDULER       │   │ fixed rate        │  │ own rate          │
     │ horizon: H ms   │   │ (OQ-6: ~50 Hz?)   │  │                   │
     │ priority queue  │   │ full 512 frame    │  │ frame per device  │
     └────────┬────────┘   └─────────┬─────────┘  └─────────┬─────────┘
              │                      │                      │
              │  dispatch at         │                      │
              │  cue.t − latency[d]  │                      │
              └──────────────────────┴──────────────────────┘
```

**Repository fit and prerequisite.** This layer cannot be built on the current
DMX path. F4 (unpaced loop), F5 (per-iteration disk read), and F6 (persistence
as IPC) each independently defeat it. M5 is a hard prerequisite. OQ-6 — the
target DMX refresh rate — is an open question that a native-Windows measurement
must answer, and DESIGN INTENT already suggests roughly 20 ms / 50 Hz.

## 3.7 Interface sketches

PROPOSED. Illustrative Python, matching the repository's existing Pydantic
idiom. Field sets are indicative, not settled.

```python
# --- Audio analysis output -------------------------------------------------
class AudioFeatureTimeline(BaseModel):
    schema_version: int
    audio_sha256: str            # cache key, part 1
    extractor_version: str       # cache key, part 2
    analysis_config_hash: str    # cache key, part 3
    duration_seconds: float
    sample_rate: int

    tempo_bpm: float | None
    tempo_confidence: float       # 0.0–1.0

    beats:     list[TimedEvent]   # t, strength, confidence
    downbeats: list[TimedEvent]
    onsets:    list[TimedEvent]
    sections:  list[Section]      # t_start, t_end, label, confidence
    silence:   list[Span]

    bands:    BandEnergySeries    # fixed hop; named bands, not bin indices
    loudness: Series
    spectral_centroid: Series

    overrides: ManualCorrections  # kept SEPARATE from generated values


# --- Show generation output ------------------------------------------------
class Cue(BaseModel):
    id: str
    t: float                      # show time, seconds
    duration: float | None
    target: TargetRef             # a fixture group or instance — never a channel
    action: CapabilityAction      # dimmer, color, strobe, pattern, haze_burst…
    params: dict[str, float | str]
    priority: int                 # higher wins on overlap
    source: Literal["generated", "manual"]
    generator_version: str | None


class ShowTimeline(BaseModel):
    schema_version: int
    audio_sha256: str
    generator_version: str
    style: str
    cues: list[Cue]               # sorted by (t, priority)


# --- Transports ------------------------------------------------------------
class DmxTransport(Protocol):
    def send_universe(self, universe: int, data: bytes) -> None: ...
    def blackout(self) -> None: ...
    def close(self) -> None: ...

class WledStateTransport(Protocol):     # JSON / WebSocket control
    def apply_state(self, device_id: str, state: WledState) -> None: ...
    def blackout(self) -> None: ...

class WledPixelTransport(Protocol):     # realtime UDP / DDP — separate on purpose
    def send_frame(self, device_id: str, pixels: bytes) -> None: ...
```

Note what is absent from `Cue`: universe, address, channel, and DMX value. If
any of those appear, the semantic boundary has been broken.

---

# Part 4 — Current state versus future state

Every major capability, with its honest label. This table is the answer to
"is this built yet?" for the whole show-control programme.

| Capability | State | Label |
| --- | --- | --- |
| DMX output, one universe, unicast sACN | Exists | VERIFIED CURRENT BEHAVIOR |
| DMX output verified against physical fixtures | No repository evidence | UNKNOWN / not HARDWARE VERIFIED |
| Multi-universe DMX | Does not exist — one `activate_output` call | VERIFIED CURRENT BEHAVIOR |
| Art-Net output | Does not exist | PROPOSED |
| OLA-backed output | Does not exist | PROPOSED |
| Mock / recording DMX transport | Does not exist for DMX; the ILDA `PointSink`/`NullSink` seam is the only precedent | VERIFIED CURRENT BEHAVIOR (of the ILDA seam) |
| Fixture patch model (universe + start address) | Does not exist; addressing is positional concatenation | VERIFIED CURRENT BEHAVIOR |
| Address-collision validation | Not possible today — there are no addresses | VERIFIED CURRENT BEHAVIOR |
| Fixture profiles as data | Does not exist; hardcoded in backend and frontend (F19) | VERIFIED CURRENT BEHAVIOR |
| Capability-based fixture model | Does not exist | PROPOSED |
| WLED direct control (JSON API) | Does not exist | PROPOSED |
| WLED WebSocket | Does not exist | PROPOSED |
| WLED realtime pixel output (UDP/DDP) | Does not exist | PROPOSED |
| LedFx scene activation by name | Exists; host/port coupling defect (F17) | VERIFIED CURRENT BEHAVIOR |
| Audio file input | **Does not exist anywhere in the repository** | PROPOSED |
| Audio decoding / normalization | Does not exist | PROPOSED |
| Offline feature extraction | Does not exist | PROPOSED |
| Cached feature artifact | Does not exist | PROPOSED |
| Live microphone onset detection | Exists, browser-side, untyped single trigger | VERIFIED CURRENT BEHAVIOR |
| Tempo / downbeat / section detection | Does not exist | PROPOSED |
| Semantic cue model | Does not exist | PROPOSED |
| Show generation from audio | Does not exist | PROPOSED |
| Manual timeline editing | Does not exist | PROPOSED |
| Monotonic playback clock / show time | Does not exist | PROPOSED |
| Lookahead scheduling | Does not exist | PROPOSED |
| Per-device latency compensation | Does not exist | PROPOSED |
| Fixed-rate DMX rendering | Does not exist; loop is unpaced (F4) | VERIFIED CURRENT BEHAVIOR |
| Full-song hardware-free simulation | Does not exist | PROPOSED |
| Fixture conformance tests | Does not exist; no test suite at all (F10) | VERIFIED CURRENT BEHAVIOR |
| Laser DAC output | Does not exist — `LoggingSink` only (F22) | VERIFIED CURRENT BEHAVIOR |
| Laser safety architecture | Does not exist | PROPOSED — see [laser_and_haze_safety.md](laser_and_haze_safety.md) |
| Haze duty-cycle control | Does not exist; `haze` is a 2-channel manual device | VERIFIED CURRENT BEHAVIOR |
| Runtime state in memory | Does not exist; `devices.json` is the bus (F6) | VERIFIED CURRENT BEHAVIOR |
| Preflight validation | Does not exist | TARGET ARCHITECTURE |
| Waveform / cue visualization | Does not exist | PROPOSED |

**Partially implemented, and the distinction matters.** Three items are neither
"exists" nor "absent":

- **Audio reactivity** is implemented *as a live trigger* and absent *as an
  analysis pipeline*. Saying "Lights has audio reactivity" is true in a way that
  will mislead every reader of this roadmap. Say which one.
- **Output adapters** exist for ILDA and only ILDA. The pattern is proven in
  this codebase; it just has not been applied to DMX or LedFx.
- **Validation on read** exists via Pydantic `TypeAdapter`
  (`backend/models/storage.py:14`). What is missing is range validation (F11),
  reference validation, and any validation of fixture semantics.

---

# Part 5 — Dependencies, assumptions, and unknowns

## Hard prerequisite chain

No show-control work should begin before the stabilization milestones it
depends on. The dependency is real, not procedural:

```text
M1 safe import ──► M2 test seams ──► Phase 1 (schemas + simulation)
                        │
                        └──► M5 runtime state + pacing ──► Phase 5 (sync)
M3 atomic storage ──────────────────► Phase 3 (artifact caching)
M8 validation/preflight ────────────► Phase 4 (lasers, haze)
M9 security ────────────────────────► Phase 4 (laser gating)
```

Concretely:

- **Phase 1 needs M2.** Without an injectable transport there is nothing to
  record, so full-song simulation cannot exist.
- **Phase 3 needs M3.** A feature-artifact cache written non-atomically will
  eventually hand a truncated artifact to a show generator, and F8 means the
  reader will report it as "empty" rather than "corrupt".
- **Phase 5 needs M5.** Synchronization on top of a disk-polling control bus
  measures disk behavior, not timing.
- **Any laser work needs M8 and M9**, and the full policy in
  [laser_and_haze_safety.md](laser_and_haze_safety.md).

## Assumptions this architecture makes

Stated so they can be challenged rather than silently inherited.

1. **One operator, one rig, one venue at a time.** No multi-user editing, no
   concurrent shows, no networked console synchronization.
2. **Audio is supplied as complete files before the show**, not streamed from a
   DJ deck in realtime. Live-input operation continues to use the existing
   microphone path (PD-6).
3. **The Python runtime stays.** The repository is Python/FastAPI end to end;
   there is no TypeScript and no frontend build step. Recommendations that
   assume a Node or TypeScript runtime are documented but are **not applicable
   to this repository** as it stands — see
   [show_control_recommendations.md](show_control_recommendations.md).
4. **Show playback is centralized in the backend.** The browser remains a
   control surface, not a scheduler.
5. **Determinism is worth more than sophistication.** A simpler generator whose
   output can be diffed and regression-tested beats a better-sounding one that
   cannot.

## Known unknowns

These are genuine gaps, recorded so no one has to rediscover them.

| Unknown | Why it matters | Where it is tracked |
| --- | --- | --- |
| Exact channel layouts for every fixture and mode | Nothing may be output without a manual-verified profile | [fixture_and_transport_strategy.md](fixture_and_transport_strategy.md), PD-3 |
| Whether the existing `MODE_VALUES` table is correct | It is the only fixture data in the repository and is unverified | F19, PD-3 |
| Target DMX refresh rate | Drives the whole synchronization design | OQ-6 |
| Whether audio playback happens in the browser or the backend | Determines where authoritative show time lives | PD-7 |
| Per-device latency values | Cannot be derived; must be measured on the rig | Phase 5 |
| Whether WLED is addressed directly or only through LedFx | Determines whether realtime pixel output is even reachable | PD-8 |
| Licensing of several candidate libraries | Affects whether a packaged executable may be distributed | [show_control_recommendations.md](show_control_recommendations.md) |
| Whether the operator wants generated shows at all, versus better tools for authoring them by hand | Would reorder Phases 3 and 5 entirely | PD-10 |

The last one is not rhetorical. This entire programme assumes generated shows
are wanted. If the real need is a better manual authoring surface with audio
alignment, the audio-analysis layer is still required but the show-generation
layer shrinks to almost nothing.
