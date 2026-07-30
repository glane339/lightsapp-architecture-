# Audio-Reactivity Architecture

**Status of this document:** PROPOSED. Established on branch
`docs/lighting-audio-show-control-architecture` against HEAD `bc91b77`.

**No part of the offline audio pipeline described here exists.** There is no
audio-file input, no decoder, no analyzer, no cache, and no timeline anywhere in
this repository. The only audio code that exists is the live browser microphone
path described in Part 1, and it is a different mechanism serving a different
purpose.

Read [show_control_architecture.md](show_control_architecture.md) first; this
document expands its audio-analysis and show-generation layers.

---

# Part 1 — What exists today

## VERIFIED CURRENT BEHAVIOR

All audio handling in Lights lives in one file: `frontend/js/home.js` (322
lines), loaded by both `frontend/index.html` and `frontend/html/active.html`.

```text
navigator.mediaDevices.getUserMedia({audio:{deviceId:{exact:id}}})
        │
        ▼
AudioContext → MediaStreamSource → AnalyserNode
        │   fftSize = 2048, smoothingTimeConstant = 0.2      home.js:198-200
        ▼
requestAnimationFrame loop  →  getByteFrequencyData(dataArray)
        │
        ▼
spectral flux over FFT bins 2..6, weighted 1.8 → 1.0         home.js:106-109
        │   rolling history of 30 frames
        │   threshold = (mean + stdDev × multiplier) × 1.22   home.js:132
        │   requires: flux > threshold
        │             flux > 20 (minimum absolute)
        │             previous flux < threshold × 0.62 (dip)
        │             flux − lastFlux ≥ 18 (sharp rise)       home.js:135-139
        │   cooldown 80 ms                                    home.js:17,94
        ▼
POST /api/active-scene/advance                                home.js:150
        │
        ▼
advance_and_apply()   → index = (index + 1) % len(preset_ids)
                      → apply that preset
                      → if PLAYER.is_beat_synced(): advance one ILDA frame
                                            backend/routes/active_scene.py:48-66
```

### What this is, precisely

It is an **onset-triggered preset cycler**. Each detected transient in the
40–100 Hz region advances an index by one. That is the entire relationship
between music and lights in Lights today.

### What it is not

- Not a tempo estimator. There is no BPM anywhere in the running code.
- Not a beat tracker. There is no phase, no grid, and no prediction.
- Not downbeat-aware. Bar position does not exist.
- Not section-aware. Verse, chorus, buildup, and drop do not exist.
- Not confidence-scored. A trigger either fires or does not.
- Not tunable by the operator. `SENSITIVITY` is a hardcoded `25`
  (`home.js:18`), alongside four other hardcoded constants.
- Not recorded. Nothing persists what fired or when, so nothing is reproducible
  or reviewable after the fact.

### Consequences worth naming

Because advancement is `index + 1` per onset, the *lighting* state is a function
of onset **count**, not of musical time. A single missed or spurious onset
permanently offsets the show from that point forward, with no mechanism to
recover. A dense passage advances the scene faster than a sparse one regardless
of tempo. And because `POST /api/active-scene/advance` triggers the full preset
application chain — which writes `devices.json` (F6) — every detected onset
causes a disk write on the control path.

None of this is an argument that the microphone path should be removed. It is a
live-performance fallback that works without preparation, and PD-6 proposes
keeping it. It is an argument that it cannot be the foundation for
synchronized show control.

---

# Part 2 — Why complete-file analysis is better than microphone-only

## The core asymmetry

A microphone analyzer knows only the past. A file analyzer knows the whole
track before the first cue fires. Every advantage below follows from that one
difference.

**Future event awareness.** The scheduler can dispatch a cue *before* the moment
it must land, absorbing network and render latency. A realtime analyzer
structurally cannot: by the time it detects the transient, the transient has
already happened, and every downstream delay is added to an already-late
trigger.

**Beat and downbeat alignment.** Offline beat tracking sees the whole tempo
curve and can place a consistent grid, including across tempo drift. Downbeats —
which require bar-level structure — are effectively unavailable to a
single-pass realtime detector, and they are what make a "big hit" land on the
right beat rather than merely on *a* beat.

**Buildup and drop detection.** A buildup is defined by what follows it. A
realtime analyzer can guess from rising energy; a file analyzer can locate the
drop exactly and then work *backwards* to time the buildup, the pre-drop
silence, and the haze cue that must fire fifteen seconds early.

**Song-section changes.** Verse/chorus/bridge boundaries come from repetition
structure across the whole track. This is not a realtime-computable quantity in
any meaningful sense.

**Silence detection.** Trivially reliable offline, and it is what prevents the
rig from strobing into an unintended gap.

**Confidence scoring.** Offline analysis can report *how sure* it is per event
class, letting the generator degrade gracefully — for example, using
downbeat-aligned cues only where downbeat confidence is high and falling back to
beat-aligned cues elsewhere.

**Precomputed cue timing.** Cue placement becomes a solved problem before
playback starts, so the runtime does only scheduling and rendering.

**Reproducible shows.** The same file plus the same versions produces the same
show. This is what makes regression testing possible at all, and it is the
property the current path most conspicuously lacks.

**Manual correction.** An operator can fix a mis-detected downbeat once and have
it stay fixed. Nothing analogous is possible for a live analyzer.

**Style-based generation.** With structure known in advance, a "restrained"
style can genuinely hold back through verses and commit at the chorus, rather
than reacting uniformly to whatever crosses a threshold.

## What microphone input keeps

Honest accounting: live input remains better for anything unprepared — a guest
DJ, a live band, an unplanned track. It needs no setup, no file, and no
analysis. PD-6 proposes both paths coexist, with the offline path as the primary
show mechanism and the live path as the fallback, sharing the same cue
vocabulary.

---

# Part 3 — The audio analysis layer

## 3.1 Decoding and normalization

**One decode boundary, once, at the top.** FFmpeg decodes MP3, WAV, FLAC, AAC,
M4A, and the rest into a canonical representation, and every analyzer downstream
consumes that same signal.

Proposed canonical form:

- mono, produced by downmix (stereo information is not used by any proposed
  feature);
- 32-bit float;
- one project-wide analysis sample rate — 22 050 Hz is the conventional choice
  for music-information-retrieval work and halves analysis cost, but the value
  belongs in the analysis config and contributes to the cache key;
- peak- or loudness-normalized, with the applied gain recorded in the artifact.

Invoke FFmpeg as a **subprocess**, not as a linked library. This keeps the
licensing boundary clean (Part 6), keeps decoder crashes out of the application
process, and avoids a heavyweight binding dependency. It does mean FFmpeg
becomes an external runtime prerequisite that PyInstaller packaging must
account for — see the risk register in
[show_control_recommendations.md](show_control_recommendations.md).

**Fail closed.** An undecodable file produces an explicit error. It must never
produce a silent or zero-length signal that the generator then treats as a
valid quiet track.

## 3.2 Feature extraction

Every extractor is versioned, deterministic, and independently testable against
a fixed input. Proposed feature set, all time-aligned to the same hop:

| Feature | Purpose | Notes |
| --- | --- | --- |
| Tempo (BPM) | Grid, and pacing of generated cues | Single global estimate plus, where supported, a tempo curve |
| Beats | Primary rhythmic anchor | With per-beat strength and confidence |
| Downbeats | Bar-level anchors for major hits | The highest-value and least reliable feature; confidence is essential |
| Onsets | Short accents | Distinct from beats: an onset is any transient, a beat is a grid position |
| Loudness / energy | Overall intensity envelope | Drives intensity profiles |
| Frequency-band energy | Bass/low-mid/mid/high-mid/treble series | **Named bands, never bin indices.** The current code's "bins 2–6" is exactly the coupling to avoid |
| Spectral centroid | Brightness → palette/colour-temperature mapping | |
| Harmonic / percussive split | Separates sustained washes from hits | Enables the two most useful mappings in Part 4 |
| Sections | Structural boundaries | Boundaries matter more than labels; a correct boundary with an unknown label is still useful |
| Silence spans | Restraint and safety | Prevents output during gaps |

**Confidence is not optional.** Each event class carries a confidence value, and
the generator is required to consult it. A downbeat track at 0.3 confidence
should not be driving the biggest fixture hits in the show.

## 3.3 Caching

Cache key = **audio content SHA-256 + extractor version + analysis config
hash**. All three. Omitting any one produces stale artifacts that are extremely
hard to diagnose:

- omit the content hash and a re-encoded file silently reuses old analysis;
- omit the extractor version and an algorithm change is invisible;
- omit the config hash and a sample-rate or hop change is invisible.

Artifacts live under `LIGHTSAPP_DATA_DIR`, in their own subdirectory, and are
written **atomically** — which is why Phase 3 depends on M3. They are treated as
a derived cache: deleting the directory must cost only recomputation time, never
data.

## 3.4 Manual correction

Generated values and manual corrections are stored **in separate structures**
within the artifact. Re-running analysis replaces the generated values and
preserves the overrides.

This is a schema decision, not a UI decision, and getting it wrong is expensive:
if a correction is applied by editing the generated array in place, the next
re-analysis silently discards the operator's work. The override record should
carry what was changed, the original value, and when — enough to re-apply after
an extractor upgrade, or to report honestly that it can no longer be re-applied.

## 3.5 Determinism requirements

- No wall-clock time, locale, or randomness in any extractor.
- Any random-seeded algorithm records its seed in the artifact.
- Library versions are recorded in the artifact and are part of the extractor
  version.
- The same input must produce a byte-identical artifact on Linux and Windows, or
  the difference must be understood and documented. Cross-platform floating-point
  differences in analysis libraries are a real possibility and should be
  measured in Phase 3 rather than assumed away.

---

# Part 4 — Recommended cue mappings

## PROPOSED, and configurable by design

These are **design patterns, not hardcoded rules.** Every one belongs in a style
definition that an operator can edit, override per show, or ignore entirely. If
any of these appears as an `if` in the generator's source rather than as data in
a style, that is a defect.

| Audio feature | Lighting response | Rationale |
| --- | --- | --- |
| Bass energy | Pulse strength / dimmer envelope on wash fixtures | Bass is the felt pulse of the track and maps naturally to perceived intensity |
| Onset strength | Short accents — brief hits on a subset of fixtures | Onsets are transient; the response should be too |
| Downbeats | Major fixture hits, full-rig moments | Bar starts are where big changes read as intentional rather than random |
| Spectral centroid | Colour temperature or palette position | Brighter timbre → cooler/brighter palette. Cheap and surprisingly effective |
| Harmonic energy | Sustained washes, slow colour movement | Harmonic content is what sustains; sustained light should follow it |
| Percussive energy | Strobes, chases, derby movement | Percussive content is what hits; hitting light should follow it |
| Section boundaries | Scene transitions | The moment the operator would have pressed the button |
| Quiet sections | Restrained output, reduced fixture count, lower intensity ceiling | Restraint is what makes the loud sections read as loud |
| Silence spans | Blackout or hold, never strobe | Also a safety property |
| Sustained buildup | Rising intensity, narrowing colour, haze pre-charge | The one mapping that genuinely requires future knowledge |
| Section-level atmosphere | **Haze** | See the constraint below |

## The haze constraint, stated as a rule

**Haze must never be mapped to beat-level or onset-level features.** Haze is a
section-level atmosphere control with warm-up time, a duty cycle, and a physical
cooldown. Mapping it to a beat produces rapid on/off cycling that is bad for the
machine, useless visually (haze does not respond that fast), and potentially a
fire-safety and alarm concern.

This is a binding constraint on any style definition, and it is stated normatively
in [laser_and_haze_safety.md](laser_and_haze_safety.md). PD-9 proposes it as a
decision.

## Style, intensity profile, and fixture groups

Three orthogonal knobs, kept orthogonal:

- **Style** — *which* mappings are active and how they compose ("percussive",
  "ambient", "high-energy").
- **Intensity profile** — a global ceiling and curve applied over the whole show
  ("restrained", "club"), independent of style.
- **Fixture groups** — *which* fixtures a mapping targets. Groups are named in
  cues; fixture instances are resolved later, in the fixture layer.

Keeping these separate is what allows one analysis to drive a small rig gently
and a large rig hard without regenerating anything but the render.

---

# Part 5 — Conflict resolution and determinism in generation

## Cue priority

Cues overlap constantly — a section-transition cue and a downbeat hit will
collide on purpose. Resolution rules, PROPOSED:

1. Higher `priority` wins for the same target and capability.
2. Equal priority: **manual beats generated**, always.
3. Still tied: later `t` wins, then stable cue-ID ordering, so the result is
   deterministic rather than dependent on iteration order.
4. Safety-gated capabilities (laser emission, haze output) are **never**
   resolved by priority. They are gated by the policy in
   [laser_and_haze_safety.md](laser_and_haze_safety.md), and a high-priority cue
   does not override a closed gate.

Rule 4 is the important one. Priority is a *creative* mechanism; safety gating
is not, and the two must not share a code path.

## Regeneration

Regenerating a show from the same artifact, generator version, style, and
overrides must produce an identical `ShowTimeline`. This makes the generator
diffable, which makes it reviewable, which is the only practical way to evaluate
whether a change to the generator improved anything.

Manual cue edits survive regeneration by the same mechanism as analysis
overrides: they are stored separately and re-applied, not merged into the
generated set.

---

# Part 6 — Library candidates for this layer

Full analysis, including prerequisites and impact ratings, is in
[show_control_recommendations.md](show_control_recommendations.md). The summary
relevant to audio:

| Library | Role | Licensing position — **verify before adopting** |
| --- | --- | --- |
| FFmpeg | Decode and normalize | LGPL or GPL depending on how the binary was built. Invoking it as a separate process avoids linking questions; **redistributing** a build inside a PyInstaller bundle does not, and needs review |
| Librosa | Baseline extraction — beats, onsets, tempo, spectral features, HPSS | Permissive (ISC). The recommended starting point |
| Essentia | Advanced structure, downbeats, higher-level descriptors | **AGPL-3.0 with a separate commercial option.** This is a genuine distribution concern for a packaged executable and must be resolved before adoption, not after |
| aubio | Lightweight onset/pitch/tempo, realtime-capable | GPL-3.0. Same distribution concern |
| NumPy / SciPy | Band extraction, filtering, resampling, smoothing | BSD. Already a partial dependency (`numpy` is in `requirements.txt`, currently unreachable — F24) |

**Every licence above must be confirmed against the upstream project at the time
of adoption.** They are recorded here to flag that a licence question exists,
not as a legal conclusion. The AGPL and GPL entries are flagged because Lights
is packaged and distributed as a Windows executable
(`build_exe.py`, `lightsapp.spec`), which is precisely the situation those
licences constrain.

**Sequencing recommendation.** Build the whole pipeline on FFmpeg + Librosa +
NumPy/SciPy first. Only after the artifact schema, cache, and generator are
working should Essentia be evaluated — and evaluated behind the same extractor
interface, so that adopting or rejecting it is a configuration change rather
than a rewrite. This also defers the AGPL question until there is evidence it is
worth answering.

---

# Part 7 — What must be true before this layer is built

1. **M2** — a test suite exists, so extractors can be regression-tested against
   fixed inputs.
2. **M3** — atomic writes exist, so a truncated artifact cannot be silently read
   back as empty (F7 + F8 together are exactly this failure).
3. **A decision on PD-7** — whether authoritative show time comes from browser
   playback or backend playback. The analysis layer does not care, but the
   scheduler does, and building the artifact format without knowing is fine
   while building the scheduler without knowing is not.
4. **An answer to PD-10** — whether generated shows are actually wanted. The
   analysis layer is required either way; the generator's size depends entirely
   on the answer.
