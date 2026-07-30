# Live Audio-Reactivity Architecture

**Status of this document:** TARGET ARCHITECTURE accepted by decisions D-13
through D-20; PROPOSED implementation detail. Updated on branch
`docs/live-renderer-architecture`.

This document expands the audio, musical-state, transition, and replay
boundaries in the canonical
[live show-control architecture](show_control_architecture.md). It does not
redefine the renderer or fixture layers.

**The future pipeline described below does not exist.** There is no
system-audio loopback source, backend capture interface, normalized feature
stream, live musical-state estimator, audio-file decoder, analysis cache, or
replay harness in this repository.

---

# Part 1 — Current audio behavior

## VERIFIED CURRENT BEHAVIOR

The supported audio-reactive path is `frontend/js/home.js`:

```text
selected browser microphone
        ↓
MediaStreamSource → AnalyserNode
        ↓
low-bin spectral-flux threshold
        ↓
POST /api/active-scene/advance
        ↓
advance one preset index and, when configured, one ILDA frame
```

It uses `fftSize = 2048`, `smoothingTimeConstant = 0.2`, a rolling flux history,
an 80 ms cooldown, and hardcoded thresholds. Despite the console label
`[Beat]`, it is an onset-triggered preset cycler:

- no tempo estimate;
- no beat grid or phase;
- no musical-state estimate;
- no confidence;
- no track-transition model;
- no deterministic recording;
- no direct WLED or fixture-aware render output.

`frontend/js/ai_mode.js` contains browser-side feature calculations for five
frequency bands, a spectral centroid, energy, and a heuristic feature vector.
That page is unlinked and functionally orphaned: its backend imports a deleted
package, so its routes are omitted. The code is evidence of prior exploration,
not a supported feature schema or a working second audio path.

The current microphone path can remain available during migration. It must not
be described as system-audio loopback, tempo tracking, or the proposed
normalized analyzer.

---

# Part 2 — Live-first party mode

## TARGET ARCHITECTURE — accepted by D-13 through D-20

The primary operating condition is a party with an unpredictable Spotify
queue. Tracks may be selected or skipped by other people, and Lights usually
will not have the original file before playback. Whole-file analysis cannot be
a required startup step for that mode.

```text
Live audio capture = runtime source of truth
Spotify metadata   = optional identity and track-change enhancement
Offline analysis   = optional prepared-track capability
```

System-audio capture is preferred because it receives the program signal
without room acoustics, crowd noise, or microphone placement. Microphone input
is the fallback when loopback is unavailable. Metadata may identify a track,
confirm a skip, or help find a known cached artifact; it does not replace
captured audio, and this architecture does not assume Spotify metadata APIs
provide arbitrary raw audio.

Offline analysis remains valuable for:

- prepared tracks and special events;
- cached analysis for a known track;
- manual corrections where future structure matters;
- regression fixtures;
- comparison of live estimates with a full-track reference.

It is optional, not the ordinary party-mode dependency.

---

# Part 3 — Source-independent capture

A future `AudioSource`-equivalent boundary supplies timestamped chunks, source
health, and discontinuity information. The exact interface is unresolved, but
implementations may include:

- WASAPI loopback on supported Windows hosts;
- an equivalent supported loopback mechanism on another operating system;
- microphone input;
- decoded audio-file input;
- deterministic click tracks and synthetic signals;
- recorded capture replay.

WASAPI is a candidate implementation, not a permanent architectural
commitment. Capture selection and device-specific behavior stay behind the
boundary. Downstream components do not inspect an operating-system source type
to decide how music should be interpreted.

The source boundary must represent at least:

- monotonic timestamps;
- expected versus observed chunk timing;
- gaps and discontinuities;
- source start, stop, pause, and failure;
- a stable source identity for diagnostics;
- enough format metadata to normalize the signal.

Exact audio formats, buffering APIs, process placement, and device-selection
rules are future implementation choices.

---

# Part 4 — Shared normalized features

Live capture, decoded files, synthetic signals, and replay eventually produce
the same conceptual feature frames:

| Feature | Intended meaning |
| --- | --- |
| Timestamp | Monotonic position associated with the observation |
| RMS or relative loudness | Short-window signal level after defined normalization |
| Bass, mid, treble energy | Named frequency regions, not FFT-bin indexes |
| Spectral centroid or brightness | Relative distribution toward higher frequencies |
| Spectral flux or onset strength | Degree of positive spectral change |
| Beat probability | Confidence that the current position is beat-related |
| Estimated tempo | Smoothed live tempo hypothesis |
| Beat phase | Position within the estimated beat cycle |
| Confidence | Quality of the estimate or feature family |

This is vocabulary, not a frozen schema. Exact names, units, band edges,
normalization windows, hop sizes, confidence semantics, and estimator
algorithms must be defined and versioned during implementation.

Two rules are already fixed:

1. Downstream state and cue logic consume normalized features, not raw capture
   APIs or FFT-bin indexes.
2. An offline feature timeline is a time-indexed form of the same vocabulary,
   not a separate language that requires another cue engine.

Rolling normalization must adapt to the current program without amplifying
silence or permanently carrying the previous track's loudness range into the
next one.

---

# Part 5 — Stabilized musical state

The analyzer produces live estimates rather than definitive song-section
labels. A candidate state vocabulary is:

- `quiet`;
- `groove`;
- `building`;
- `peak`;
- `breakdown`;
- `transition`;
- `unknown`.

The estimator combines recent feature history with confidence. It must use:

- smoothing to suppress frame-to-frame noise;
- hysteresis so entering and leaving a state need not use the same threshold;
- confidence thresholds and an honest `unknown` outcome;
- minimum residence times where rapid switching would be visually unstable;
- transition rules that control which state changes may happen immediately.

For example, one loud frame should not flip `groove → peak → groove`. A
sustained rise with increasing onset strength and reliable beat evidence may
support `groove → building`; a confirmed drop may support `building → peak`.
Those examples do not select an algorithm.

The state estimator does not claim to know “verse” or “chorus” from a short
live window. Offline structure analysis may supply richer annotations for a
prepared track, but they must still enter cue generation through compatible
state or event concepts.

---

# Part 6 — Track and source transitions

Transition evidence may come from:

- sustained silence;
- pause or playback stop;
- abrupt tempo shift;
- abrupt loudness or spectral change;
- a manual skip;
- metadata-reported track change, when available;
- capture loss or recovery.

Metadata is corroborating evidence, not the sole runtime truth. Conversely,
silence alone does not prove a new track; it may be an intentional break.

On a likely transition, the runtime evaluates which history remains useful.
The following may require gradual reset:

- tempo history;
- beat phase;
- bar counter;
- rolling loudness and band normalization;
- musical-state confidence;
- effect progression.

Output should normally fade or pass through a restrained transition state.
Hard resets are reserved for explicit safety actions or policies that require
them. Loss of input must have a defined safe behavior: for example, fade to a
restrained hold, then blackout after a configured interval. The exact policy is
unresolved, but leaving the last energetic frame latched indefinitely is not
acceptable.

---

# Part 7 — Timing and overload behavior

Initial nonbinding budgets are:

- audio chunks around 10–20 ms;
- feature updates around 50–100 Hz;
- musical-state updates around 20–50 Hz;
- end-to-end visual response under approximately 80 ms.

These figures are engineering targets to measure, not guarantees. System-audio
capture, Python processing, queueing, WLED rendering, DMX output, device
latency, and fixture response all contribute.

Queues between live stages are bounded and latest-state-wins. If an analyzer
or consumer falls behind, obsolete chunks and feature frames are skipped
rather than processed late. Diagnostics record dropped inputs, dropped render
frames, queue depth, and observed stage latency.

Offline decoding is not subject to live deadlines, but it must produce the same
time basis and feature semantics so it can enter the estimator or cue engine
without a source-specific branch.

---

# Part 8 — Semantic mapping, not channel mapping

Audio interpretation ends at semantic visual intent. Representative mappings
include:

| Musical evidence or state | Semantic response |
| --- | --- |
| Reliable beat or onset | Pulse a wash group or accent bars |
| Rising energy / `building` | Raise scene intensity within the active ceiling |
| `peak` with confidence | Trigger a short drop burst or pixel chase |
| Brightness shift | Move a palette position |
| `quiet` or uncertain input | Reduce fixture count, intensity, and effect rate |
| Transition | Fade, hold, or inhibit progression while estimates re-stabilize |
| Atmosphere request | Adjust haze only through slow safety policy |

This layer does not emit DMX channel values, WLED packet fields, or LedFx HTTP
payloads. It may explicitly request that laser output be held or inhibited, but
it cannot enable the laser master gate. Haze must never be mapped directly to
beat- or onset-level features.

---

# Part 9 — Offline analysis and caching

Offline analysis is a later, optional capability. It may add:

- file decoding;
- cached normalized feature timelines;
- future-aware structure and silence annotations;
- prepared shows;
- known-track lookup;
- separately stored manual corrections.

A future cache key should include audio content identity, analyzer version, and
analysis configuration. Exact hashing, file formats, algorithms, and library
choices remain implementation decisions. Cached analysis is an enhancement:
failure to find or load it returns party mode to live analysis rather than
preventing playback.

Future knowledge has legitimate special uses. Haze lead time, manually
corrected section boundaries, and a deliberately prepared drop can use a
complete-file timeline. Those capabilities supplement the live renderer; they
do not make it source-dependent.

---

# Part 10 — Capture and replay testing

Deterministic replay is the primary regression mechanism:

```text
captured audio or synthetic signal
        ↓
normalized feature-frame log
        ↓
musical-state log
        ↓
semantic cue log
        ↓
recorded WLED and DMX output
```

Each log boundary allows a test to replay the output of one stage into the
next. This isolates whether a change came from capture normalization, feature
extraction, state stabilization, cue policy, or rendering.

The planned corpus covers:

- click tracks;
- constant tempo and tempo changes;
- silence;
- bass-heavy and bright/treble-heavy material;
- noisy microphone input;
- abrupt skips;
- quiet-to-loud changes;
- loss and recovery of audio input.

The same capture and configuration must produce deterministic downstream logs,
subject to explicitly documented numerical tolerances where byte identity is
not portable. No replay test may reach real hardware.

---

# Part 11 — Implementation language

Python is the primary language for capture integration, feature extraction,
state estimation, cue orchestration, scheduling, rendering, transports, and
backend integration. This keeps the first implementation aligned with the
existing FastAPI and Pydantic application.

Rust or C++ is considered only behind a stable interface after profiling on
representative hardware shows a demonstrated bottleneck. An assumed need for
native performance is not enough to add another runtime or packaging boundary.

---

# Part 12 — State summary

| Capability | Documentation state |
| --- | --- |
| Browser microphone onset trigger | VERIFIED CURRENT BEHAVIOR |
| Browser AI feature page | Orphaned current code; not a working feature |
| System-audio loopback | TARGET ARCHITECTURE (D-14); not implemented |
| Microphone fallback through the future source boundary | TARGET ARCHITECTURE (D-14); not implemented |
| Shared feature vocabulary | TARGET ARCHITECTURE (D-15); exact schema unresolved |
| Live musical-state estimator | TARGET ARCHITECTURE; not implemented |
| Transition detection and gradual reset | TARGET ARCHITECTURE; not implemented |
| Audio-file analysis and cache | Optional planned capability; not implemented |
| Recorded capture replay | Approved testing direction; not implemented |
| Spotify metadata enhancement | Optional future capability; not implemented |
