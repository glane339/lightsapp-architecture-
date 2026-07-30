# Live Show-Control Architecture

**Status of this document:** canonical TARGET ARCHITECTURE, accepted by
decisions D-13 through D-20; PROPOSED for implementation details. Updated on branch
`docs/live-renderer-architecture`.

**The live analyzer, normalized feature stream, musical-state estimator,
semantic cue engine, native WLED renderer, fixture-aware DMX renderer, replay
harness, and safety policy described below are not implemented.** Part 1
records the current behavior that does exist. Evidence labels are defined in
[project_overview.md](project_overview.md).

This is the canonical description of the future live renderer. Companion
documents add detail without redefining the architecture:

| Document | Responsibility |
| --- | --- |
| [audio_reactivity_architecture.md](audio_reactivity_architecture.md) | Audio sources, normalized features, live state estimation, transitions, and replay |
| [fixture_and_transport_strategy.md](fixture_and_transport_strategy.md) | Fixture profiles, capability rendering, LedFx compatibility, WLED, and DMX output |
| [laser_and_haze_safety.md](laser_and_haze_safety.md) | Normative laser and atmosphere policy |
| [show_control_roadmap.md](show_control_roadmap.md) | Dependency-ordered delivery phases |
| [decisions.md](decisions.md) | Accepted decisions and unresolved implementation choices |

---

# Part 1 — Current implementation

## VERIFIED CURRENT BEHAVIOR

Lights is currently a single-operator, single-rig, single-universe controller
with an onset-triggered preset cycler. It is not yet the live show-control
system described later in this document.

| Boundary | Current behavior |
| --- | --- |
| Audio | `frontend/js/home.js` captures a selected browser microphone, computes spectral flux over low FFT bins, and posts one advance event after a qualifying onset. It does not estimate tempo, beat phase, confidence, or musical state. |
| Orphaned AI audio code | `frontend/js/ai_mode.js` computes several per-frame values, but its backend package was deleted and the routes are omitted at startup. It is not a functioning analyzer or a supported feature schema. |
| Active show | Each accepted onset advances the active preset index. Lighting progression therefore depends on onset count rather than a musical clock. |
| LedFx and WLED | `backend/ledfx/client.py` can list and activate LedFx scenes by name over synchronous HTTP. Lights contains no direct WLED state client and no realtime pixel transport. |
| DMX | `backend/dmx/mapper.py` sorts devices by `order`, concatenates `active_channels`, pads or truncates to 512 values, and sends one configured sACN universe. Addressing is positional; fixtures have no explicit universe or start address. |
| DMX runtime | The sender is created at import. Its application loop is unpaced and re-reads `devices.json` on every iteration. Persistent JSON is the live control bus. |
| Fixtures | `gigbar`, `keobin`, and `haze` behavior is hardcoded across backend and frontend. No fixture-profile or capability-renderer system exists. |
| Lasers | The ILDA path ends at `LoggingSink` and cannot emit through a DAC. DMX-attached laser channels are reachable through ordinary presets and have no master gate. |
| Haze | A two-channel manual `haze` device is bootstrapped. No duty-cycle, warm-up, cooldown, or rate policy exists. |
| Testing | There is no conventional automated test suite or deterministic audio/frame replay harness. |

The current browser microphone path remains useful evidence and a fallback, but
it is not the future architecture. The target does not promote its raw FFT-bin
mapping or per-onset HTTP advancement into the renderer.

---

# Part 2 — Primary use case and governing model

## TARGET ARCHITECTURE — accepted by D-13 through D-20

Lights is primarily intended to run at parties where Spotify playback and its
queue can change continuously and unpredictably. The application usually will
not possess the original audio file before a track starts. A design that
requires whole-file analysis before playback therefore cannot be the primary
party mode: the file may never be available, a guest may skip the track, and
the next selection may be unknown until the transition occurs.

The governing model is:

```text
Live audio capture = runtime source of truth
Spotify metadata   = optional identity and track-change enhancement
Offline analysis   = optional prepared-track capability
```

Spotify metadata may help identify a track, confirm a change, or locate cached
analysis for known material. It is not an audio source, and this architecture
does not assume Spotify metadata APIs expose arbitrary raw playback audio.

System-audio loopback is the preferred party-mode source because it observes
the program signal before room acoustics, crowd noise, and microphone placement
alter it. Microphone capture remains the fallback when loopback is unavailable
or inappropriate. Audio-file analysis remains valuable for prepared tracks,
cached analysis, testing, and special events, but it is not a prerequisite for
ordinary party operation.

## Canonical conceptual flow

```text
Audio sources
├── System-audio loopback — preferred party-mode source
├── Microphone — fallback source
├── Audio file — prepared-track and testing source
└── Recorded/replayed capture — deterministic testing source
          ↓
Normalized real-time audio features
          ↓
Stabilized musical state
          ↓
Semantic cue/effect engine
          ↓
Fixture-aware rendering
├── LedFx compatibility adapter
├── Native WLED renderer
└── DMX renderer
    ├── PARs and bars
    ├── multi-effect fixtures
    ├── safety-gated lasers
    └── rate-limited haze/atmosphere
```

Live and offline inputs must eventually produce the same normalized
audio-feature vocabulary. Downstream state estimation and cue generation
consume that vocabulary rather than branching on whether samples came from
loopback, a microphone, a decoded file, or a replay log.

---

# Part 3 — Four-stage renderer

The future renderer has four conceptual stages:

1. **Feature normalization** converts a source-specific signal into a
   source-independent feature stream.
2. **Musical-state estimation** stabilizes noisy observations into useful live
   estimates.
3. **Semantic cue generation** decides what visual or atmospheric action is
   appropriate.
4. **Device- and fixture-specific rendering** translates that intent into
   LedFx scene changes, WLED state or pixel output, and complete DMX universe
   frames.

This layering is the architecture. Exact class names, module layout, schemas,
and algorithms remain future implementation choices unless
[decisions.md](decisions.md) records otherwise.

## Why FFT bins do not map directly to RGB

A direct FFT-to-RGB mapping couples capture settings, sample rate, FFT size,
room response, and device channels into one fragile function. It also makes
several desired behaviors difficult or impossible:

- smoothing a musical transition without blurring every pixel calculation;
- coordinating WLED and DMX fixtures around the same intent;
- enforcing laser, strobe, intensity, and atmosphere policy before output;
- preserving a recognizable style across different rigs;
- comparing a LedFx scene with a native effect at the same semantic boundary;
- replaying one capture deterministically through changed estimators or
  renderers.

Frequency information is evidence about the music. It is not itself a lighting
command.

---

# Part 4 — Audio-source and feature boundaries

## Future audio-source abstraction

The source boundary is source-independent. Candidate implementations include:

- WASAPI loopback on supported Windows hosts, or the equivalent supported
  system-audio capture mechanism on another platform;
- microphone input;
- audio-file playback or decoding;
- deterministic synthetic signals;
- recorded capture replay.

The interface must expose timestamped audio or feature-ready chunks plus
source health and discontinuity information. It must not permanently bind the
architecture to WASAPI, a browser API, or any single operating system.
Platform-specific capture remains behind the boundary.

## Normalized feature stream

The intended conceptual vocabulary includes:

- timestamp;
- RMS or relative loudness;
- bass, mid, and treble energy;
- spectral centroid or brightness;
- spectral flux or onset strength;
- beat probability;
- estimated tempo;
- beat phase;
- confidence.

Additional named bands or descriptors may be justified by measured renderer
needs. Raw FFT-bin indexes are not a stable public vocabulary. Exact field
names, units, sample windows, normalization rules, and algorithms are unresolved
implementation decisions and must be versioned when defined.

Live processing produces feature frames continuously. Offline analysis may
produce a cached timeline, but each point on that timeline must be expressible
in the same vocabulary so the next stage is source-agnostic.

---

# Part 5 — Live musical-state estimation and transitions

## Stabilized runtime states

Candidate live estimates are:

- `quiet`;
- `groove`;
- `building`;
- `peak`;
- `breakdown`;
- `transition`;
- `unknown`.

These names describe an evolving runtime belief, not definitive offline song
sections such as verse or chorus. A live analyzer can infer that energy is
building without claiming knowledge of what the future track structure will
be.

The estimator requires smoothing, hysteresis, confidence thresholds, minimum
residence times where useful, and explicit transition handling. Without those
controls, momentary noise or one uncertain frame would cause unstable effect
switching. Low confidence should prefer `unknown`, hold a safe prior state, or
degrade to restrained cues rather than invent certainty.

## Track-transition detection

Transition evidence may include:

- sustained silence;
- pause or playback stop;
- abrupt tempo shift;
- abrupt loudness or spectral change;
- a manual skip signal;
- a metadata-reported track change, when available.

No one signal is universally authoritative. Metadata can strengthen a
transition decision but is optional; captured audio remains the runtime truth.

The estimator may need to reset or gradually re-seed:

- tempo history;
- beat phase;
- bar counter;
- rolling normalization;
- effect progression.

Transitions should normally fade, hold, or move through a restrained
`transition` state instead of hard-resetting every device. A pause or loss of
input follows the configured safe loss-of-signal policy, not an arbitrary last
frame.

---

# Part 6 — Semantic cue boundary

Semantic cues describe visual or operational intent without physical channel
values. Representative outputs include:

- pulse wash fixtures;
- trigger a pixel chase;
- advance or shift a palette;
- accent bars;
- raise scene intensity;
- trigger a drop burst;
- hold or inhibit laser output;
- adjust atmosphere within safety limits.

A semantic cue may name a fixture group, capability, intensity, duration,
priority, or transition shape. It does not name “DMX channel 14” or value 255.
Universe, start address, protocol packet, WLED endpoint, and fixture-specific
range lookup belong below this boundary.

Safety gates are not cue priorities. A high-priority cue cannot open the laser
gate, exceed a strobe limit, bypass an intensity ceiling, or defeat an
atmosphere rate limit.

---

# Part 7 — Incremental LedFx and native-renderer migration

LedFx is the compatibility path, not an obstacle to remove immediately:

```text
Current LedFx integration
        ↓
Custom real-time analyzer and semantic cue engine
        ↓
├── LedFx adapter for existing WLED scenes
├── Native WLED renderer for new pixel effects
└── DMX renderer for physical fixtures
```

Lights first gains ownership of audio normalization, musical state, and
semantic cues. Existing WLED scenes can continue through an injectable LedFx
adapter while native output grows beside it. LedFx remains available until
native effects are demonstrably reliable on supported hardware and parity has
been evaluated for the scenes operators rely on.

Ownership of each WLED device must be unambiguous at runtime. LedFx and the
native renderer must not concurrently fight for the same device.

## Native WLED modes

Two future output modes are distinct:

1. **State-oriented control** for power, presets, brightness, segments, colors,
   palettes, and other lower-rate changes.
2. **Realtime pixel streaming** for custom per-pixel effects at a render-frame
   rate.

Realtime streaming likely uses a supported protocol such as DDP, but DDP is not
an architectural commitment. Transport selection must be validated against the
actual WLED firmware, hardware, pixel count, network, and measured performance.
Pixel frames must not be tunneled through the lower-rate state path.

## Fixture-aware DMX rendering

The future DMX loop runs at a fixed rate and:

1. reads the latest normalized state and active semantic effects;
2. evaluates effects for the current tick;
3. resolves target fixtures, layers, and priorities;
4. builds a complete frame for each configured universe;
5. applies safety policy and safe values;
6. sends through an injectable real, null, or recording transport.

The renderer is latest-state-wins. It does not replay a backlog of stale
intermediate states.

Fixture instances require explicit universe and 1-based start-address
configuration. Complete frames are built by placing validated fixture output at
those addresses, not by positional channel concatenation. PARs, bars, and
multi-effect fixtures are rendered by declared capabilities and exact,
manual-sourced fixture modes. Unknown modes and unsafe profiles fail closed as
specified in [fixture_and_transport_strategy.md](fixture_and_transport_strategy.md).

---

# Part 8 — Safety boundary

The renderer and runtime require explicit policy controls for:

- emergency blackout that is independent of cue evaluation;
- laser master enable, off on every start and requiring deliberate operator
  confirmation;
- strobe-rate and exposure limits;
- global and per-fixture intensity ceilings;
- haze or atmosphere duty-cycle, minimum-off, and rate limits;
- manual override with defined precedence;
- freeze or hold behavior that distinguishes creative hold from emergency
  blackout;
- safe loss-of-signal behavior for missing audio, renderer failure, transport
  failure, and disconnect.

The detailed laser and haze requirements are normative in
[laser_and_haze_safety.md](laser_and_haze_safety.md). Software policy reduces
ways the application can command unintended output; it does not guarantee
legal compliance or venue safety and does not replace physical interlocks,
appropriate emergency stops, correct installation, or a trained operator.

---

# Part 9 — Scheduling and latency budgets

The following are initial, nonbinding engineering budgets:

| Stage | Initial target |
| --- | --- |
| Audio chunks | approximately 10–20 ms |
| Feature updates | approximately 50–100 Hz |
| Musical-state updates | approximately 20–50 Hz |
| Native WLED rendering | approximately 30–60 frames per second |
| DMX output | approximately 30–44 frames per second |
| Capture-to-visible response | under approximately 80 ms end to end |

These are not guarantees, supported-hardware claims, or fixed constants. They
must be measured on actual supported hardware, including the Windows show host,
WLED devices, DMX node, fixture response, and real network.

Inter-stage handoffs use bounded latest-state-wins queues. If processing misses
a deadline, stale feature or render frames are skipped rather than accumulated.
The runtime must expose dropped-frame counts and latency measurements so budget
violations can be diagnosed instead of hidden.

---

# Part 10 — Deterministic testing and replay

Replay is the primary regression strategy for the live system:

```text
Captured audio or synthetic signal
        ↓
Feature-frame log
        ↓
Musical-state log
        ↓
Semantic cue log
        ↓
WLED frame log and DMX universe log
```

Each boundary is recordable and replayable. Tests can therefore distinguish an
audio-normalization change from a state-estimation change, a cue-policy change,
or a fixture-rendering change.

The planned fixture corpus includes:

- click tracks;
- constant tempo;
- tempo changes;
- silence;
- bass-heavy material;
- bright or treble-heavy material;
- noisy microphone input;
- abrupt skips;
- quiet-to-loud changes;
- loss and recovery of audio input.

Recorded live capture and synthetic signals are first-class test inputs, not
debug leftovers. Recording transports must capture WLED and complete DMX output
without contacting physical devices. Simulation validates software behavior,
not fixture profiles or hardware response; native-Windows rig validation
remains separate under [platform_support.md](platform_support.md).

---

# Part 11 — Language and optimization strategy

Python remains the primary implementation language for:

- audio analysis;
- cue orchestration;
- scheduling;
- fixture rendering;
- transports;
- backend integration.

This matches the existing FastAPI/Pydantic application and keeps the first
implementation within one runtime. Rust or C++ may be introduced behind a
stable project-owned interface only after profiling on representative hardware
demonstrates a bottleneck that cannot be resolved acceptably in Python. Native
code is an optimization response, not an architectural starting assumption.

---

# Part 12 — Current state versus future direction

| Capability | State |
| --- | --- |
| Browser microphone spectral-flux onset trigger | VERIFIED CURRENT BEHAVIOR |
| System-audio loopback capture | TARGET ARCHITECTURE (D-14); not implemented |
| Source-independent audio interface | TARGET ARCHITECTURE (D-14); not implemented |
| Spotify metadata enhancement | Optional future capability; not implemented |
| Spotify raw-audio ingestion | Not assumed or planned through metadata APIs |
| Audio-file decoding and offline analysis | Optional future capability; not implemented |
| Normalized shared feature vocabulary | TARGET ARCHITECTURE (D-15); schema unresolved and not implemented |
| Stabilized live musical-state estimation | TARGET ARCHITECTURE; algorithms unresolved and not implemented |
| Semantic cue model | TARGET ARCHITECTURE (D-16); not implemented |
| LedFx scene activation | VERIFIED CURRENT BEHAVIOR, with known configuration and timeout defects |
| LedFx compatibility adapter | TARGET ARCHITECTURE (D-17); injectable adapter not implemented |
| Direct WLED state control | PROPOSED implementation; not present |
| Native realtime WLED pixels | TARGET ARCHITECTURE (D-17); transport unresolved and not present |
| One-universe positional sACN output | VERIFIED CURRENT BEHAVIOR |
| Explicit fixture patch and fixed-rate DMX renderer | TARGET ARCHITECTURE; not implemented |
| Laser, strobe, intensity, and atmosphere policy | TARGET ARCHITECTURE (D-20); controls not implemented |
| Deterministic capture/replay and output logs | TARGET ARCHITECTURE (D-19); not implemented |

## Unresolved implementation choices

The architecture deliberately leaves these choices open until evidence exists:

- exact live-capture APIs and where capture runs;
- the normalized feature schema, units, windows, and algorithms;
- state-estimation algorithms and thresholds;
- Spotify metadata integration scope and authentication;
- WLED realtime transport and supported firmware/hardware matrix;
- measured queue sizes, rates, latency budgets, and overload behavior;
- fixture-profile format and exact manual-verified channel definitions;
- operator behavior for freeze, hold, and loss of signal within the required
  safety policy.

These choices may refine the implementation. They may not collapse the
source-independent feature boundary, the semantic cue boundary, the
fixture-aware rendering boundary, or the explicit safety gates.
