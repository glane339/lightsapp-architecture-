# Show-Control Recommendations

**Status of this document:** PROPOSED. Established on branch
`docs/lighting-audio-show-control-architecture` against HEAD `bc91b77`.

Every entry is a recommendation, not a decision. Nothing here is adopted,
installed, or implemented. Adopting any of them requires an owner decision, and
several require a licence review first.

Read [show_control_architecture.md](show_control_architecture.md) for the layer
model these recommendations sit inside.

## How to read the impact ratings

| Rating | Meaning |
| --- | --- |
| **Transformative** | Unlocks a major capability or substantially changes what the app can do |
| **High** | Materially improves reliability, extensibility, accuracy, or hardware support |
| **Moderate** | Useful, but not essential to the core design |
| **Low** | Optional convenience or future enhancement |

Ratings are **qualitative and justified in prose**. No numerical percentage
appears anywhere in this document, because this repository has no benchmarks
from which one could be derived — consistent with the prohibition on completion
percentages in decision D-10.

## The one repository fact that reshapes several recommendations

**This repository is Python end to end.** `backend/` is FastAPI and Pydantic;
`frontend/` is vanilla JavaScript with **no build step, no package.json, and no
TypeScript**. Confirmed against the tracked file list at HEAD `bc91b77`.

Recommendations written for a Node or TypeScript runtime — the Node/TS Art-Net
library, the Node/TS sACN library, and Zod — are therefore **not applicable to
this repository as it stands**. They are documented in full, because the
question "should Lights adopt a Node runtime?" is legitimate and the answer
should be on record rather than assumed. But adopting any of them means adopting
a second runtime first, and that is a much larger decision than the library
choice it appears to be.

---

# Summary matrix

| # | Recommendation | Layer | Impact | Applicable to this repo? |
| --- | --- | --- | --- | --- |
| 1 | WLED JSON API | Transport | High | Yes |
| 2 | WLED WebSocket | Transport | High | Yes |
| 3 | WLED realtime UDP/DDP | Transport | **Transformative** | Yes |
| 4 | Official WLED repo and docs | Reference | Moderate (High maintenance value) | Yes |
| 5 | `python-wled` | Transport | Moderate | Yes |
| 6 | WLED-MM | Research | Moderate | Yes, as reference only |
| 7 | Open Lighting Architecture | Transport | High | Conditional — Windows caveat |
| 8 | PyArtNet | Transport | High | Yes |
| 9 | Node/TS Art-Net library | Transport | High *if* Node | **No** — no Node runtime |
| 10 | Node/TS sACN library | Transport | Moderate–High *if* Node | **No** — no Node runtime |
| 11 | Mock and recording DMX transports | Transport / Test | High | Yes — highest-leverage early item |
| 12 | Open Fixture Library | Fixture | High | Yes, with licence review |
| 13 | QLC+ definitions and validation | Fixture | Moderate–High | Yes |
| 14 | Project-owned fixture schema | Fixture | **Transformative** | Yes — the keystone |
| 15 | Capability-based fixture model | Fixture | **Transformative** | Yes |
| 16 | FFmpeg | Audio | High | Yes, with packaging review |
| 17 | Librosa | Audio | **Transformative** | Yes |
| 18 | Essentia | Audio | High | Yes, **blocked on AGPL review** |
| 19 | Aubio | Audio | Moderate | Yes, GPL review |
| 20 | NumPy and SciPy | Audio | High | Yes |
| 21 | Cached audio feature artifact | Audio | High | Yes |
| 22 | Manual analysis correction | Audio | High | Yes |
| 23 | Monotonic playback clock | Sync | **Transformative** | Yes |
| 24 | Lookahead scheduler | Sync | High | Yes |
| 25 | Per-device latency compensation | Sync | High | Yes |
| 26 | Fixed-rate DMX rendering | Sync | High | Yes |
| 27 | Audio timeline + semantic cue model | Schema | **Transformative** | Yes |
| 28 | Pydantic (not Zod) | Schema | High | Yes — already a dependency |
| 29 | XState or explicit state machines | App | Moderate | Partially — see entry |
| 30 | Fixture conformance tests | Test | **Transformative** | Yes |
| 31 | Full-song simulation | Test | High | Yes |
| 32 | Universe collision validation | Test | High | Yes, after addressing exists |
| 33 | Visual timeline and waveform diagnostics | Test / UX | High | Yes, machine-readable first |
| 34 | Context7 | Agent tooling | Moderate | Yes |
| 35 | GitHub MCP | Agent tooling | Moderate | Yes |
| 36 | Superpowers development skills | Agent tooling | High | Yes |
| 37 | Custom Lights skills | Agent tooling | High | Yes |

---

# 1. WLED

## 1.1 WLED JSON API

**What it does.** Controls WLED power, brightness, colours, segments, presets,
effects, and device state over HTTP with JSON request and response bodies.

**Why it is relevant here.** Lights currently has **no direct WLED control at
all**. WLED is reached only by asking LedFx to activate a scene by name
(`backend/ledfx/client.py`), which means Lights cannot set a brightness, change
a colour, or address a segment. Every WLED behaviour must be pre-authored as a
LedFx scene. Direct JSON control is the baseline capability that removes that
constraint.

**How it would be implemented here.** A `WledStateTransport` behind an internal
interface, constructed by the composition root and injected — the same shape as
the DMX transport, and modelled on the existing `PointSink` protocol
(`backend/ilda/sink.py`). Device address, and any per-device latency offset, come
from the fixture instance record. **Raw API calls must not appear in route
handlers or frontend code**, which is exactly the mistake the current LedFx
integration makes: `LEDFXClient` is constructed inline in
`backend/routes/post.py` at the point of use.

**Prerequisites.** M1 (import safety) and M2 (injection seam). M7 matters
directly: F17 couples the only existing outbound host to `config.server_host`,
so a second network destination is not expressible in the current config model.

**Risks and licensing.** WLED's JSON API evolves across firmware versions; pin
and record supported versions per device. No licence concern — this is an HTTP
API, not a dependency.

**Expected improvement: High.** Substantial increase in what Lights can express
on WLED devices, and it removes a hard dependency on LedFx for basic control.

## 1.2 WLED WebSocket interface

**What it does.** Two-way communication with a WLED device: state pushes without
polling, and lower-latency control.

**Why it is relevant here.** The current status path polls — a 1 Hz asyncio task
performs a LedFx HTTP GET on every tick (F16), with no timeout on that call. A
push-based state channel removes that class of work entirely for WLED devices.

**How it would be implemented here.** Connection lifecycle owned by the
composition root and the FastAPI lifespan; explicit reconnect with backoff;
state normalized into the same internal model the JSON transport produces, so
consumers cannot tell which channel delivered an update; a test double that
replays recorded frames.

**Prerequisites.** 1.1 first — the state model should exist before a second
channel populates it. M1 for lifecycle ownership.

**Risks and licensing.** Reconnect logic is where this kind of integration
usually fails; it needs explicit states (see entry 29) rather than boolean
flags. No licence concern.

**Expected improvement: High.** Moderate reduction in integration effort, and a
material improvement in state freshness and responsiveness versus polling.

## 1.3 WLED realtime UDP or DDP output

**What it does.** Streams pixel-frame data to WLED devices at high rate, rather
than issuing individual state commands.

**Why it is relevant here.** This is the capability that makes tightly
synchronized pixel effects possible. Neither the JSON API nor LedFx scene
activation can drive per-frame pixel content from a show timeline. Without it,
WLED devices can only be told "run this effect" — they cannot participate in a
cue-accurate show.

**How it would be implemented here.** A **separate** `WledPixelTransport`, not
an overload of the JSON path. Different rate, different failure semantics
(fire-and-forget rather than request/response), different lifecycle. It is
driven by the synchronization layer's pixel tick, not by cue dispatch.

**Prerequisites.** Entry 3 depends on 23 (monotonic clock) and 26 (fixed-rate
rendering) to be worth anything, on M5 for the runtime-state separation, and on
a `pixel_frame` capability in the fixture model (entry 15).

**Risks and licensing.** Network load scales with pixel count times frame rate,
and WLED devices have real throughput limits. Unlike DMX, there is no
standards-body pacing to hide behind. WSL2 cannot validate any of this
(D-8) — it needs the native-Windows rig. No licence concern.

**Expected improvement: Transformative for advanced pixel effects.** It is the
difference between WLED as a preset selector and WLED as a show fixture.

## 1.4 Official WLED repository and documentation

**What it does.** The authoritative reference for supported protocols, APIs,
effects, limits, and firmware behaviour.

**Why it is relevant here.** Entries 1.1–1.3 are all protocol integrations, and
the failure mode for protocol integrations is building against a blog post or a
wrapper's assumptions instead of the source. Given that Lights has no WLED code
today, every line of it will be written from some reference; it should be this
one.

**How it would be implemented here.** Cited in the integration documentation,
with **supported WLED firmware versions pinned and recorded per device** in the
instance record. A firmware version that has not been checked is an unknown, and
the fixture model should be able to say so.

**Prerequisites.** None.

**Risks and licensing.** None. Reference use only.

**Expected improvement: Moderate direct, High maintenance value.** Small direct
user-facing improvement, but it is the difference between an integration that
survives a firmware update and one that mysteriously stops working.

## 1.5 `python-wled`

**What it does.** A Python client library for WLED devices.

**Why it is relevant here.** The runtime is Python, so a maintained client could
remove a meaningful amount of protocol code from entries 1.1 and 1.2.

**How it would be implemented here.** **Behind a project-owned adapter, with its
types never crossing the WLED integration boundary.** This is not ceremony: the
existing LedFx integration shows what happens without it — `LEDFXClient` is
constructed at the call site and its behaviour is not substitutable, which is
why F16 and F17 are difficult to fix. The internal interface should be defined
first and the library evaluated against it, not the other way round.

**Prerequisites.** The internal WLED interface (1.1) must exist first, or the
library's shape will define the boundary by default.

**Risks and licensing.** Adds a dependency to a `requirements.txt` that is
currently **entirely unpinned** (F21) — adoption should come with pinning.
Library async/sync model may not match the surrounding code. Believed
permissively licensed; **verify at adoption**. Coverage of realtime pixel output
should not be assumed.

**Expected improvement: Moderate.** Moderate reduction in integration effort;
no user-visible capability that 1.1 does not already provide.

## 1.6 WLED-MM

**What it does.** A WLED fork focused on advanced and audio-reactive behaviour.

**Why it is relevant here.** Its audio-reactive effect implementations are a
design reference for the cue-mapping patterns in
[audio_reactivity_architecture.md](audio_reactivity_architecture.md) — a
worked example of which audio features map usefully to which visual behaviours.

**How it would be implemented here.** **As a research source only.** Study
selected algorithms and mapping choices. Do not make Lights depend on the fork,
and do not require operators to run it, unless a specific capability is
identified and justified separately.

**Prerequisites.** None for reference use.

**Risks and licensing.** A fork's protocol behaviour may diverge from upstream
WLED; do not generalize from it when implementing 1.1–1.3. Its licence is
inherited from WLED and matters only if code is reused, not if ideas are.

**Expected improvement: Moderate as a research source.** Small direct
user-facing improvement, real value in avoiding first-principles guesswork about
audio-to-visual mappings.

---

# 2. DMX transports

## 2.1 Open Lighting Architecture (OLA)

**What it does.** A mature lighting-control daemon and abstraction layer
supporting USB-DMX hardware, Art-Net, sACN, and other outputs behind one
interface.

**Why it is relevant here.** Lights is coupled to exactly one output method:
sACN over the network, via a module-global `SENDER` (F3). OLA would provide
hardware independence, including USB-DMX interfaces that Lights cannot use at
all today.

**How it would be implemented here.** Run `olad` on the show host; implement an
OLA-backed `DmxTransport` alongside the existing sACN one. Universe mapping
becomes configuration.

**Prerequisites.** M1 and M2 (the transport must be injectable). Entry 14 for
multi-universe addressing to be meaningful.

**Risks and licensing.** **The significant one is deployment.** Lights deploys as
a native-Windows PyInstaller executable
([platform_support.md](platform_support.md)); OLA's Windows support is
materially weaker than its Linux support. Adopting it means either accepting a
Linux show host — a large change to the deployment model — or treating OLA as a
Linux-and-development option while Windows uses sACN or Art-Net. **Decide this
before Phase 2, not during.** Adding a daemon also adds a process-lifecycle and
failure surface. Licensing is copyleft (daemon and libraries differ); running
`olad` as a separate process and communicating over its interface is the clean
boundary. **Verify at adoption.**

**Expected improvement: High for hardware flexibility and reliability** — but
conditional on the Windows question. Unresolved, the realistic rating for this
repository is Moderate.

## 2.2 PyArtNet

**What it does.** An asynchronous Python library for Art-Net and related
lighting protocols.

**Why it is relevant here.** The runtime is Python and the deployment is
network-DMX. Many DMX nodes speak Art-Net but not sACN, or are simply easier to
commission with Art-Net. This is the lightest-weight way to stop being
single-protocol.

**How it would be implemented here.** A `DmxTransport` implementation sending
complete universe frames, driven by the fixed-rate render tick (entry 26) rather
than by an unpaced loop. Fades and synchronized multi-universe output are
handled at the transport where the library supports them.

**Prerequisites.** M1, M2, entry 26. Its async model needs to be reconciled with
the current threaded sender — a design point, not a detail.

**Risks and licensing.** Async/threaded impedance mismatch with the existing
code. Adds a dependency to an unpinned `requirements.txt` (F21). **Licence
UNKNOWN to this document — verify before adoption**, because a copyleft licence
would affect the packaged Windows executable.

**Expected improvement: High for a Python implementation.** Materially broader
hardware support for modest effort.

## 2.3 Node or TypeScript Art-Net library

**What it does.** Sends Art-Net DMX frames from a Node or TypeScript runtime.

**Why it is relevant here.** **It is not, as the repository stands.** The
recommendation presumes a TypeScript runtime; this repository has none — no
`package.json`, no build step, no TypeScript anywhere in the tracked file list.

**How it would be implemented here.** Only after a decision to introduce a Node
runtime for the show engine. It would be wrapped behind the same `DmxTransport`
interface used by the tests and the other transports, so the interface work
(entry 11) is not wasted either way.

**Prerequisites.** A runtime decision that has not been made and is not
currently proposed.

**Risks and licensing.** Introducing a second runtime brings a second dependency
tree, a second packaging story on Windows, a second set of CI matrices, and a
cross-runtime IPC boundary — against a repository whose current problems are
about too little structure, not too few languages.

**Expected improvement: High if the runtime were Node; not applicable here.**
Recorded so the option is on the record rather than silently assumed away.

## 2.4 Node or TypeScript sACN library

**What it does.** Transmits E1.31/sACN universes from a Node runtime.

**Why it is relevant here.** Same as 2.3 — not applicable without a runtime
change. Note additionally that Lights **already has** working sACN output in
Python, so this would replace something that works rather than add a capability.

**How it would be implemented here.** As a separate adapter behind
`DmxTransport`, never with protocol logic embedded in the show engine — the
principle holds regardless of runtime.

**Prerequisites.** A Node runtime decision.

**Risks and licensing.** As 2.3, plus the risk of regressing a currently working
output path.

**Expected improvement: Moderate to high if the runtime were Node; not
applicable here.**

## 2.5 Mock and recording DMX transports

**What it does.** Captures generated universe frames with timestamps instead of
transmitting them to fixtures.

**Why it is relevant here.** This is **the highest-leverage single item in the
entire programme for this repository**, and the argument is specific: Lights has
no test suite (F10), no injectable output (F3), and a policy that hardware is
unavailable (D-2) on a platform that cannot validate hardware behaviour (D-8).
A recording transport is what converts "we cannot test output" into "we can test
output exhaustively without a rig".

**How it would be implemented here.** Two implementations behind `DmxTransport`:
a null transport that discards, and a recording transport that appends
`(show_time, universe, 512-byte frame)` records to a file that both the test
suite and the future visualizer (entry 33) read. The existing `NullSink` /
`LoggingSink` pair (`backend/ilda/sink.py`) is the proven in-repository
precedent and should be the model.

**Prerequisites.** M1, then M2. Nothing else.

**Risks and licensing.** Recording files grow quickly at 50 Hz across a full
track; needs a retention policy. Frames must be compared with a stable
normalization so tests fail on real differences rather than on timing jitter.
No licence concern — this is project code.

**Expected improvement: High for reliability and development speed.** It is the
prerequisite for entries 30, 31, 32, and 33, and a substantial reduction in the
amount of work that requires the rig.

---

# 3. Fixture definitions

## 3.1 Open Fixture Library

**What it does.** A normalized open database and schema of stage-lighting
fixture definitions.

**Why it is relevant here.** F19: fixture behaviour is hardcoded across backend
and frontend, and adding a fixture requires code changes in multiple layers.
OFL could supply ready definitions for the common PARs and bars, so that manual
profile authoring is reserved for the unusual fixtures.

**How it would be implemented here.** An **importer into the project-owned
schema** (entry 14), never a runtime dependency on the external format.
Imported profiles arrive with `verified: false` and are blocked from physical
output until checked against the manufacturer manual and the physical fixture.

**Prerequisites.** Entry 14 must exist first — there is nothing to import into
otherwise.

**Risks and licensing.** Coverage of the specific rig fixtures is uncertain, and
a definition that is right for a similar model can be confidently wrong for
this one. **Licence terms for the fixture definition data must be verified
before any imported profile ships inside the packaged executable** — this is a
redistribution question, and a share-alike data licence would constrain it.

**Expected improvement: High.** Substantial reduction in per-fixture authoring
effort for common fixtures; no help at all for the composite fixtures that are
the hard part of this rig.

## 3.2 QLC+ fixture definitions and validation

**What it does.** An established lighting application with a broad fixture
library and DMX/Art-Net/sACN output.

**Why it is relevant here.** Two distinct uses, and the second is the more
valuable one. As a **fixture-definition source**, it is a second opinion
alongside OFL. As a **known-good test controller**, it lets an operator verify
what a fixture actually does, independently of Lights — which is the only way to
resolve "is the profile wrong or is Lights wrong?" without guessing.

**How it would be implemented here.** Import or cross-check fixture definitions
into the project schema. Separately, use QLC+ during rig commissioning to
establish ground truth for each fixture and mode before writing the Lights
profile.

**Prerequisites.** Entry 14. The test-controller use has none.

**Risks and licensing.** Definition quality is community-contributed and varies.
**Verify licence terms before redistributing any imported definition.** Using
QLC+ as a bench tool carries no licensing implication for Lights.

**Expected improvement: Moderate to high.** Moderate as a definition source;
high as a verification tool, because it is the mechanism that makes
"HARDWARE VERIFIED" achievable for fixture profiles at all.

## 3.3 Project-owned fixture schema

**What it does.** An internal, versioned representation of manufacturers,
models, modes, channels, capabilities, addresses, and universes.

**Why it is relevant here.** It is **the keystone of the entire programme**.
Without it there is nothing for the show generator to target, nothing for
renderers to consume, nothing to validate, and no way to remove the hardcoded
`gigbar`/`keobin`/`haze` branches from four files. Every other fixture-related
recommendation depends on it existing.

**How it would be implemented here.** Pydantic models — already the repository's
idiom — with runtime validation on read, as `backend/models/storage.py` already
does via `TypeAdapter`. Separate `FixtureDefinition` (what a product is) from
`FixtureInstance` (what is in this rig), as sketched in
[fixture_and_transport_strategy.md](fixture_and_transport_strategy.md). Profile
version is a first-class field, and profile tests plus address-collision
validation ship with it.

**Prerequisites.** M3 (typed read outcomes) and M8 (validation layer). It is
M10's substance.

**Risks and licensing.** The migration from positional to explicit addressing is
the highest-risk change in the programme — it changes bytes on the wire for a
working rig. The staged, byte-identical migration in
[fixture_and_transport_strategy.md](fixture_and_transport_strategy.md) Part 3
exists for exactly this. No licence concern.

**Expected improvement: Transformative.** Substantial reduction in
fixture-specific code, and it converts "add a fixture" from a multi-layer code
change into a data entry task.

## 3.4 Capability-based fixture model

**What it does.** Represents fixtures by what they can *do* — dimmer, RGB
colour, strobe, pan, tilt, laser enable, pattern, haze output, fan speed —
rather than by what they are called.

**Why it is relevant here.** It is what allows the show engine to emit
`strobe the bars` without knowing a channel number, and it is the mechanism
behind the semantic boundary (PD-1). It also collapses the renderer count: one
`dimmer` renderer serves every fixture that declares a dimmer.

**How it would be implemented here.** A small, deliberately constrained
capability vocabulary; mode-specific renderers registered per capability; pure
render functions with golden-frame tests (entry 30). Capabilities a mode does
not declare cause the cue to be dropped and recorded — never approximated.

**Prerequisites.** Entry 14.

**Risks and licensing.** The vocabulary will be under constant pressure to grow
for one unusual fixture; resist, and prefer a fixture-specific `macro_select`
over a capability that only one product understands. Composite fixtures
(GigBAR, Keobin) do not map cleanly to a single fixture with one capability set
— they need the multi-logical-fixture modelling described in
[fixture_and_transport_strategy.md](fixture_and_transport_strategy.md). No
licence concern.

**Expected improvement: Transformative.** Substantial reduction in
fixture-specific code, and it is what makes one generated show portable across
rigs.

---

# 4. Audio processing

## 4.1 FFmpeg

**What it does.** Decodes and normalizes MP3, WAV, FLAC, AAC, M4A, and more into
a consistent PCM representation.

**Why it is relevant here.** It creates **one** decoding boundary. Every
analyzer downstream then operates on an identical signal, which is a
precondition for the determinism the whole pipeline depends on.

**How it would be implemented here.** Invoked as a **subprocess**, producing
canonical mono float PCM at the project analysis sample rate, with applied gain
recorded in the artifact. A decode failure is an explicit error, never a silent
empty signal.

**Prerequisites.** None architecturally; it is the first stage.

**Risks and licensing.** **Packaging is the real risk.** FFmpeg is an external
binary, and the Windows PyInstaller build (`build_exe.py`, `lightsapp.spec`)
would need to locate or bundle it — bundling makes it a redistribution question.
Licensing is LGPL or GPL **depending on how the binary was built**; invoking it
as a separate process avoids linking concerns, but shipping a build inside the
executable does not. **Resolve before packaging, not after.**

**Expected improvement: High.** Major improvement in format coverage and in the
reproducibility of everything downstream.

## 4.2 Librosa

**What it does.** A Python music-and-audio analysis library: beat tracking,
onsets, tempo, spectral features, loudness, chroma, harmonic/percussive
separation.

**Why it is relevant here.** It is the fastest path from "no audio pipeline at
all" to a working offline analysis, and it covers most of the feature set in
[audio_reactivity_architecture.md](audio_reactivity_architecture.md) Part 3.2 in
one dependency.

**How it would be implemented here.** Versioned extractor functions, each
deterministic and independently testable against fixed inputs, writing into the
cached artifact (entry 21). Each extractor sits behind an interface so it can be
replaced without touching the artifact schema.

**Prerequisites.** 4.1 for decoding; M2 for regression testing; M3 for atomic
artifact writes.

**Risks and licensing.** Analysis is CPU-intensive — a full track takes real
time, which is why caching is not optional. Downbeat and section quality vary by
genre and are the features most likely to need manual correction (entry 22).
Permissively licensed (ISC); **verify at adoption**. Brings a substantial
scientific-Python dependency tree, which interacts with the packaged-executable
size.

**Expected improvement: Transformative for offline sound reactivity.** It is the
single dependency that makes the audio-analysis layer exist.

## 4.3 Essentia

**What it does.** An advanced music-information-retrieval library with rhythm,
tonal, timbral, structural, and higher-level algorithms.

**Why it is relevant here.** Downbeat detection, section detection, and drop
identification are the three features with the highest show-quality payoff and
the lowest reliability from a baseline pipeline. Essentia is the strongest
candidate for improving exactly those.

**How it would be implemented here.** **Only after the Librosa baseline works**,
and behind the same extractor interface, so adopting or rejecting it is a
configuration change rather than a rewrite. Optional dependency; the pipeline
must remain fully functional without it.

**Prerequisites.** 4.2, entry 21, and a **licence decision**.

**Risks and licensing.** **This is the entry with the most serious licence
concern in this document.** Essentia is understood to be AGPL-3.0 with a
separate commercial option. Lights is built and distributed as a Windows
executable, which is precisely the situation that licence constrains. **This
must be resolved before adoption, not after** — and deferring Essentia until the
baseline pipeline proves it is needed also defers the question until there is
evidence it is worth answering. Installation is also heavier than Librosa's.

**Expected improvement: High for advanced analysis** — major improvement in
downbeat and structural accuracy, gated entirely on the licence question.

## 4.4 Aubio

**What it does.** A smaller audio-analysis toolkit for onset, pitch, tempo,
beat, and spectral analysis, including realtime-capable operation.

**Why it is relevant here.** Two possible roles: a lighter alternative to
Librosa for the subset of features it covers, and a candidate for a
**backend-side realtime** path if live audio analysis ever moves out of the
browser.

**How it would be implemented here.** Behind the extractor interface, evaluated
against the same fixed-input tests as the Librosa extractors so the comparison
is empirical rather than anecdotal.

**Prerequisites.** The extractor interface (4.2).

**Risks and licensing.** Feature coverage is narrower than Librosa's; adopting
it as the primary extractor would leave gaps. Understood to be GPL-3.0 — the
same distribution concern as Essentia, at a smaller benefit. **Verify at
adoption.**

**Expected improvement: Moderate.** Small direct user-facing improvement given
Librosa covers the baseline; real value only if a realtime backend path is
wanted.

## 4.5 NumPy and SciPy

**What it does.** Core numerical tooling: filtering, interpolation, transforms,
resampling, and feature calculation.

**Why it is relevant here.** Named frequency-band extraction, smoothing, and
resampling to a common hop are all custom work that no analysis library will do
in exactly the form the cue mappings need. This is where the project's own
signal processing lives.

**How it would be implemented here.** Isolated, tested, parameterized functions
— pure, deterministic, no I/O. `numpy` is **already in `requirements.txt`**
(`numpy>=1.24.0`), currently with no reachable code path (F24); this would give
it one, which also bears on OQ-7.

**Prerequisites.** 4.1.

**Risks and licensing.** Cross-platform floating-point differences between Linux
and Windows are a real possibility for a pipeline that claims determinism, and
should be **measured** in Phase 3 rather than assumed away. BSD-licensed;
permissive.

**Expected improvement: High.** Materially better control over the features that
drive cue mapping, and small direct user-facing improvement with high developer
value.

## 4.6 Cached audio feature artifact

**What it does.** A versioned file holding beats, downbeats, onsets, loudness,
band energy, tempo, sections, confidence, and metadata for one track.

**Why it is relevant here.** Analysis is slow; shows are regenerated often. More
importantly, the artifact is what makes generated shows **reproducible** —
without it, "the same show" is not a well-defined thing.

**How it would be implemented here.** Keyed by **audio content hash + extractor
version + analysis config hash** — all three. Stored under `LIGHTSAPP_DATA_DIR`
in its own subdirectory, written atomically, and treated as a derived cache that
can be deleted at the cost of recomputation only.

**Prerequisites.** **M3 is a hard prerequisite.** F7 (non-atomic writes) plus F8
(errors collapse to empty) is exactly the combination that would hand a
truncated artifact to a generator as "no beats detected".

**Risks and licensing.** Schema evolution needs a migration story from the
first version. Cache growth needs a retention policy. No licence concern.

**Expected improvement: High.** Major improvement in iteration speed and the
enabling condition for reproducibility.

## 4.7 Manual analysis correction

**What it does.** Lets an operator correct beats, sections, drops, and other
unreliable detections.

**Why it is relevant here.** Automatic analysis will be wrong for some tracks,
and a show is a performance — one wrong downbeat in a chorus is visible to
everyone in the room. Without correction, the operator's only recourse is to
abandon generation for that track.

**How it would be implemented here.** **Overrides stored separately from
generated values** in the artifact schema, so re-analysis replaces the generated
set and preserves the corrections. This is a schema decision made now, not a UI
decision made later — getting it wrong means the next re-analysis silently
discards the operator's work.

**Prerequisites.** 4.6. The UI comes later (entry 33), but the schema must
support it from the first version.

**Risks and licensing.** An override may become un-re-applicable after an
extractor upgrade; the system must say so rather than silently drop it. No
licence concern.

**Expected improvement: High for production-quality shows.** It is the
difference between a generator that works on most tracks and one that can be
relied on for a specific set.

---

# 5. Synchronization and scheduling

## 5.1 Monotonic playback clock

**What it does.** A high-resolution clock unaffected by wall-clock adjustments,
with audio playback position as the authoritative show time.

**Why it is relevant here.** **Show time does not currently exist as a concept.**
Lighting state is a function of onset *count*, not of musical time
([audio_reactivity_architecture.md](audio_reactivity_architecture.md) Part 1).
Every other synchronization recommendation presupposes this one.

**How it would be implemented here.** One clock, owned by the synchronization
layer, and the only component permitted to read time. All cues are compared
against it. Drift between the clock and actual audio position is measured and
corrected rather than accumulated.

**Prerequisites.** M5, and a decision on PD-7 (browser or backend playback) —
that decision determines where the authoritative position is read from.

**Risks and licensing.** If playback is in the browser, position must cross the
network and the transport latency becomes part of the timing budget. No licence
concern.

**Expected improvement: Transformative.** Major improvement in synchronization
accuracy, and the precondition for entries 24–26.

## 5.2 Lookahead scheduler

**What it does.** Dispatches cues slightly ahead of playback rather than
reacting when a timestamp is reached.

**Why it is relevant here.** Network, rendering, and device latency are all
additive after the trigger. Reactive dispatch means every cue is late by the sum
of them; lookahead means the pipeline delay is absorbed rather than accumulated.

**How it would be implemented here.** A priority queue over the show timeline
with a configurable horizon; dispatch at `cue.t − latency[device]`.

**Prerequisites.** 5.1, and the semantic cue model (entry 27).

**Risks and licensing.** A horizon that is too long makes seeking and live edits
awkward — cues already dispatched must be recallable. Needs an explicit
invalidation path on seek. No licence concern.

**Expected improvement: High.** Major improvement in perceived timing accuracy
for modest implementation cost.

## 5.3 Per-device latency compensation

**What it does.** Individual timing offsets per WLED device, DMX node, laser,
and haze machine.

**Why it is relevant here.** These devices respond at genuinely different
speeds, and haze differs by seconds to tens of seconds, not milliseconds
([laser_and_haze_safety.md](laser_and_haze_safety.md) 3.6). Without
compensation, "synchronized" means synchronized at the transport and visibly
unsynchronized in the room.

**How it would be implemented here.** A `latency_ms` field on the fixture
instance, consumed by the scheduler at dispatch. Haze lead time is a separate,
much larger, venue-specific value and should not be conflated with device
latency.

**Prerequisites.** 5.2, and the fixture instance model (entry 14).

**Risks and licensing.** Values cannot be derived; they must be **measured on
the rig**, which makes this native-Windows work under D-8. No licence concern.

**Expected improvement: High.** Major improvement in cross-device timing
coherence, which is the thing an audience actually perceives.

## 5.4 Fixed-rate DMX rendering

**What it does.** Produces complete DMX universe frames at a stable output
frequency.

**Why it is relevant here.** The current loop is **unpaced** (F4) and re-reads
`devices.json` on every iteration (F5). It is not merely uneven — it is a busy
loop whose iteration rate is determined by disk and CPU. DESIGN INTENT targets
roughly 20 ms / 50 Hz.

**How it would be implemented here.** Render in-memory desired state into a
512-byte universe buffer on a monotonic tick and transmit at a configured rate.
This is M5's substance, and OQ-6 is the open question about the correct default.

**Prerequisites.** **M5.** All three of F4, F5, and F6 must be fixed; each
independently defeats stable pacing.

**Risks and licensing.** The `sacn` library performs its own internal throttling;
the interaction between application pacing and library pacing needs to be
understood rather than assumed. The rate must be validated on native Windows
against the real rig (OQ-6). No licence concern.

**Expected improvement: High.** Major improvement in output determinism, and it
eliminates a continuous CPU and disk load.

## 5.5 Audio timeline and semantic cue model

**What it does.** Separates detected musical events from device-specific
commands: `AudioFeatureTimeline`, `ShowTimeline`, and `Cue` as distinct typed
schemas.

**Why it is relevant here.** It is the semantic boundary (PD-1) expressed as
types. It is what lets one analysis drive multiple rigs and multiple styles, and
it is what makes the show generator testable without any fixture at all.

**How it would be implemented here.** Pydantic models, versioned, validated on
read. **A `Cue` that contains a universe, address, channel, or DMX value is a
layering violation** and should fail review — the type should make it
impossible.

**Prerequisites.** M3 for typed read outcomes. It is Phase 1's first deliverable.

**Risks and licensing.** Schema churn early on is guaranteed; version from the
first commit. Over-designing the cue model before a real generator exists is the
main practical risk — start with the capabilities the current rig actually has.
No licence concern.

**Expected improvement: Transformative.** It is the architectural decision the
entire programme rests on.

---

# 6. Application and schema tools

## 6.1 Pydantic (not Zod)

**What it does.** Runtime validation of fixture profiles, audio artifacts, show
timelines, configuration, and external API payloads.

**Why it is relevant here.** Validated data is what stops a malformed profile
from reaching a physical fixture. Pydantic is **already the repository's model
layer** — `backend/models/` is entirely Pydantic and
`backend/models/storage.py:14` already validates through a `TypeAdapter` on
read. This is an extension of existing practice, not a new dependency.

**How it would be implemented here.** Versioned schemas for every new artifact;
validation at every boundary; field-level constraints that close F11 (DMX values
constrained to 0–255, channel-list lengths checked against declared counts).

**Zod is not applicable to this repository.** Zod is a TypeScript library, and
the frontend is vanilla JavaScript with no build step. Adopting it would require
introducing a frontend build pipeline first — a real decision with real costs,
and one that should be made on its own merits rather than as a side effect of
wanting schema validation. Backend-side Pydantic validation covers the
safety-critical path today.

**Prerequisites.** None; it is already present.

**Risks and licensing.** Pydantic is currently **unpinned** (F21), and v1/v2
behavioural differences are significant — pinning should accompany any expansion
of its use. MIT-licensed.

**Expected improvement: High.** Materially reduces the class of defects where
malformed data reaches output, and directly addresses F11.

## 6.2 XState or explicit state machines

**What it does.** Models connection, playback, pairing, reconnect, and failure
behaviour as explicit states and transitions.

**Why it is relevant here.** Several upcoming subsystems have genuine state:
WLED WebSocket connection lifecycle (1.2), playback (stopped/loading/playing/
paused/seeking), the laser master enable (which is explicitly a state machine
with a manual-confirmation transition), and haze duty-cycle tracking. Today,
`backend/routes/active_scene.py` holds runtime state as an unsynchronized
module-global dict (F14) — the current pattern does not scale to any of these.

**How it would be implemented here.** **Explicit state machines as a pattern,
not XState as a dependency.** XState is a TypeScript/JavaScript library and does
not apply to the Python backend where this state actually lives. In Python, an
enum-plus-transition-table with a lock, or a small typed state class, achieves
the same discipline. Adopt only for workflows with meaningful transitions —
not for every boolean.

**Prerequisites.** M5 and M6 (runtime state must be owned and synchronized
before it is modelled).

**Risks and licensing.** Over-application produces ceremony around simple flags.
No licence concern for the pattern.

**Expected improvement: Moderate.** Materially better reliability for
connection and playback lifecycles; no user-visible capability of its own.
**Highest value for the laser master enable**, where correct state transitions
are a safety property rather than a convenience.

---

# 7. Testing and simulation

## 7.1 Fixture conformance tests

**What it does.** Verifies that each fixture profile maps semantic actions to
the expected DMX channels, via golden channel-frame tests for every supported
mode.

**Why it is relevant here.** It is the mechanism that catches a wrong profile
**before a fixture does**. Given that lasers and strobes are in the rig, a
wrong profile is not only a visual defect.

**How it would be implemented here.** For every profile and mode, assert the
exact channel offsets and values produced by each capability. Pure render
functions (entry 15) make this straightforward. Extend to characterization
frames for the existing rig, which is what makes the addressing migration
provable (entry 14, and
[fixture_and_transport_strategy.md](fixture_and_transport_strategy.md) Part 3).

**Prerequisites.** M2, entries 14 and 15.

**Risks and licensing.** Golden tests must be regenerated deliberately, never
casually — a "just update the goldens" habit destroys the entire value. Passing
conformance tests prove the profile matches its *definition*, not that the
definition matches the *fixture*; only manual and rig verification does that.

**Expected improvement: Transformative for reliability and safety.** It is the
only automated defence against incorrect physical output.

## 7.2 Full-song simulation

**What it does.** Runs a complete generated show with no hardware connected,
recording every output frame.

**Why it is relevant here.** It makes an entire show reviewable on WSL2, where
D-2 and D-8 forbid hardware validation. Timing, transitions, output limits, and
unsafe commands all become inspectable without a rig, and diffable between
versions.

**How it would be implemented here.** Mock WLED transports plus the recording
DMX transport (entry 11), driven by the real scheduler against a real artifact.
The output is a frame log that tests assert over and the visualizer (entry 33)
renders.

**Prerequisites.** Entry 11, M2, and a working generator.

**Risks and licensing.** Simulation validates the *software*, never the
*hardware*. A show that simulates perfectly can still be wrong on the rig
because a profile is wrong — this must be stated wherever simulation results are
reported, or "simulated" will be read as "verified". No licence concern.

**Expected improvement: High.** Major reduction in the amount of work requiring
the rig, and it makes generator changes reviewable.

## 7.3 Universe collision validation

**What it does.** Detects overlapping fixture addresses and channels that exceed
universe limits.

**Why it is relevant here.** Colliding addresses mean fixtures unintentionally
control each other — which, with lasers and strobes in the rig, is a safety
concern and not only a visual one.

**How it would be implemented here.** Validate the entire patch before playback
starts, as part of preflight (M8). Reject rather than warn.

**Prerequisites.** **Explicit addressing must exist first** (entry 14). This
validation is *meaningless today*: addressing is positional concatenation, so
there are no addresses to collide — and the analogous current defect is that a
wrong-length `active_channels` list silently shifts every downstream fixture
(F11), which this validation would not catch either.

**Risks and licensing.** None significant.

**Expected improvement: High.** Prevents a whole class of confusing and
potentially unsafe misconfiguration.

## 7.4 Visual timeline and waveform diagnostics

**What it does.** Displays waveform, beats, sections, cues, fixture output, and
errors on one synchronized timeline.

**Why it is relevant here.** Diagnosing "the lights feel late" or "the drop
didn't land" from logs is close to impossible. This makes both immediately
visible, and it is also the natural surface for manual correction (entry 22) and
manual cue editing.

**How it would be implemented here.** **Machine-readable diagnostics first**, in
the same format the recording transport produces. A viewer comes later. This
ordering matters: the diagnostic format is useful to tests immediately, while
the UI is a substantial new frontend surface for a codebase with **no frontend
build step** — which is a real constraint on how much editor can reasonably be
built.

**Prerequisites.** Entries 11, 21, and 31.

**Risks and licensing.** Scope creep toward a full timeline editor is the
obvious risk; the diagnostic view and the editor are separate deliverables and
should stay separate. No licence concern.

**Expected improvement: High.** Small direct user-facing improvement at first,
very high developer and operator diagnostic value, growing to high user-facing
value if the editor follows.

---

# 8. Development and agent tooling

## 8.1 Context7

**What it does.** Supplies current, version-specific library documentation to
coding agents.

**Why it is relevant here.** This programme adds several libraries with
version-sensitive APIs — WLED firmware, Librosa, PyArtNet, Pydantic v1 versus
v2. Agents working from stale training data on an **unpinned**
`requirements.txt` (F21) is a concrete, already-present failure mode.

**How it would be implemented here.** Configured for documentation retrieval
only.

**Prerequisites.** None.

**Risks and licensing.** Adds an external service dependency to the development
loop. It does not substitute for reading the repository, and agents should not
be permitted to treat retrieved documentation as evidence about *this* codebase.

**Expected improvement: Moderate developer-productivity improvement.** No
user-facing change.

## 8.2 GitHub MCP

**What it does.** Lets coding agents inspect repositories, issues, pull
requests, workflows, and security results.

**Why it is relevant here.** Work here is organized around narrow,
milestone-scoped branches (D-12), and review discipline is explicitly the point
of that structure. Repository-aware review support fits it directly.

**How it would be implemented here.** **Restricted, primarily read-only
toolsets.**

**Prerequisites.** None.

**Risks and licensing.** Write access would let an agent act outside the
repository boundary that `CLAUDE.md` and `AGENTS.md` establish. Keep it
read-only unless a specific need justifies otherwise.

**Expected improvement: Moderate developer-productivity improvement.**

## 8.3 Superpowers development skills

**What it does.** Structured workflows for brainstorming, planning,
test-driven development, debugging, review, and verification.

**Why it is relevant here.** This repository's stated principal risk is
uncontrolled AI-generated change: D-1 (incremental, not rewrite), D-12 (narrow
first branch), and the "explicitly out of scope" list in
[current_sprint.md](current_sprint.md) all exist to contain it. Structured
workflows reinforce exactly that discipline, and the test-driven workflow maps
directly onto the requirement to write characterization tests before changing
legacy behaviour (M2).

**How it would be implemented here.** Selected skills rather than overlapping
general collections.

**Prerequisites.** None.

**Risks and licensing.** Process overhead on genuinely small changes; skills
must not override the repository's own instructions, which take precedence.

**Expected improvement: High for development reliability.** No direct
user-facing change; substantial reduction in the risk of scope-violating
changes.

## 8.4 Custom Lights skills

Six project-specific skills. Each is PROPOSED; none exists.

### `lights-fixture-profile`

- **Invoke when:** adding or modifying a fixture profile, or importing from OFL
  or QLC+.
- **Inputs:** manufacturer, exact model, manual reference and revision, DMX
  mode, channel list with capabilities and ranges.
- **Outputs:** a validated profile in the project schema with
  `verified: false`, plus generated conformance tests for every capability in
  the mode.
- **Safety checks:** refuses to mark a profile verified without an explicit
  manual citation; refuses to emit laser or haze capabilities without linking
  [laser_and_haze_safety.md](laser_and_haze_safety.md); refuses to invent
  channel numbers when the manual reference is absent.
- **Validations:** channel count matches the declared mode; no duplicate
  offsets; all ranges within 0–255; every capability has a documented safe
  value.
- **Why it helps:** fixture profiles are the highest-risk data in the system and
  the easiest for an agent to fabricate plausibly. This makes fabrication fail
  rather than pass.

### `lights-audio-analysis`

- **Invoke when:** adding or changing an audio extractor, or bumping the
  extractor version.
- **Inputs:** the extractor implementation, analysis config, and a fixed test
  audio fixture.
- **Outputs:** a versioned extractor, a regenerated artifact for the fixture,
  and a determinism test.
- **Safety checks:** refuses to change extractor behaviour without incrementing
  the extractor version; refuses to write generated values into the manual
  override structure.
- **Validations:** identical output across two runs; no wall-clock, locale, or
  unseeded randomness; artifact validates against the current schema.
- **Why it helps:** determinism is the property most easily broken by an
  innocent-looking change, and the least likely to be noticed until a show
  differs.

### `lights-show-generator`

- **Invoke when:** changing generation rules, styles, or cue mappings.
- **Inputs:** an artifact, a style, fixture groups, intensity profile.
- **Outputs:** a `ShowTimeline`, plus a diff against the previous generation for
  the same inputs.
- **Safety checks:** rejects any cue containing a universe, address, channel, or
  DMX value (the PD-1 boundary); rejects any style mapping haze to beat- or
  onset-level features (PD-9); rejects laser cues where the gate is not
  modelled.
- **Validations:** regeneration is byte-identical; manual cues survive;
  conflicts resolve deterministically.
- **Why it helps:** it makes the semantic boundary and the haze prohibition
  mechanically enforced rather than merely documented.

### `lights-dmx-safety-audit`

- **Invoke when:** before any branch that changes output, profiles, transports,
  or the scheduler merges.
- **Inputs:** the diff, the patch, the affected profiles.
- **Outputs:** a pass/fail report naming every output-affecting change.
- **Safety checks:** flags new laser or haze capabilities; flags anything that
  could transmit during import (F1–F3); flags removal or weakening of a gate,
  blackout, or watchdog; flags profiles marked verified in the same change that
  created them.
- **Validations:** channel values within range; addresses within universe
  bounds; no collisions; blackout paths still reachable.
- **Why it helps:** it puts a consistent gate in front of the class of change
  that can damage equipment or people.

### `lights-hardware-simulator`

- **Invoke when:** validating a show, a generator change, or a profile change
  without hardware.
- **Inputs:** artifact, show timeline, patch, style.
- **Outputs:** a recorded frame log and a timing report.
- **Safety checks:** asserts the null and recording transports are in use and
  that **no real transport can be reached**; refuses to run if a real
  destination is configured.
- **Validations:** no out-of-range values; no duty-cycle violations; no laser
  emission without a modelled gate; frame rate within tolerance.
- **Why it helps:** it makes hardware-free validation the default path rather
  than a special effort, which is exactly what D-2 and D-8 require.

### `lights-release-audit`

- **Invoke when:** preparing a packaged build or a release.
- **Inputs:** the tree, `requirements.txt`, the build scripts and spec.
- **Outputs:** a release readiness report.
- **Safety checks:** verifies output is disabled by default; verifies the laser
  master enable defaults off; verifies no development data directory is bundled;
  verifies no credentials or local network configuration are included.
- **Validations:** dependencies pinned (F21); licence review complete for every
  bundled component (FFmpeg, any GPL/AGPL analysis library, any redistributed
  fixture definitions); native-Windows checklist rows exercised for the
  milestones in the release.
- **Why it helps:** it is where the licensing and packaging risks scattered
  through this document get caught once, together, before distribution.

**Expected improvement across all six: High for repeatability and
project-specific quality.** No direct user-facing change; a substantial
reduction in the probability that an agent produces plausible, unverified,
output-affecting work.

---

# Dependency graph of the recommendations

```text
                        ┌──────────────────────────┐
                        │ M1 safe import           │
                        │ M2 test seams            │
                        └────────────┬─────────────┘
                                     │
        ┌────────────────────────────┼───────────────────────────┐
        ▼                            ▼                           ▼
 ┌──────────────┐          ┌───────────────────┐        ┌────────────────┐
 │ 11 mock +    │          │ 14 project        │        │ 27 timeline +  │
 │ recording    │          │ fixture schema    │◄───────│ semantic cues  │
 │ transports   │          └─────────┬─────────┘        └───────┬────────┘
 └──────┬───────┘                    │                          │
        │              ┌─────────────┼──────────────┐           │
        │              ▼             ▼              ▼           │
        │        ┌──────────┐  ┌──────────┐  ┌───────────┐      │
        │        │ 15 capa- │  │ 12 OFL   │  │ 32 colli- │      │
        │        │ bilities │  │ 13 QLC+  │  │ sion valid│      │
        │        └────┬─────┘  └──────────┘  └───────────┘      │
        │             │                                         │
        ▼             ▼                                         │
 ┌──────────────┐ ┌──────────────┐                              │
 │ 31 full-song │ │ 30 conform-  │                              │
 │ simulation   │ │ ance tests   │                              │
 └──────┬───────┘ └──────────────┘                              │
        │                                                       │
        ▼                                                       │
 ┌──────────────┐     ┌────────────────────────────────┐        │
 │ 33 timeline  │     │ 16 FFmpeg → 17 Librosa         │        │
 │ diagnostics  │     │      → 20 NumPy/SciPy          │        │
 └──────────────┘     │      → 21 cached artifact ─────┼────────┘
                      │      → 22 manual correction    │
                      │      → 18 Essentia (licence!)  │
                      └────────────────────────────────┘

  M5 runtime state ──► 23 monotonic clock ──► 24 lookahead ──► 25 latency
                                │
                                └──────────► 26 fixed-rate DMX

  M7 LedFx decoupling ──► 1 WLED JSON ──► 2 WebSocket
                                     └──► 3 realtime pixels (needs 23, 26)

  M8 preflight + M9 auth + laser gate (PD-4) ──► laser capabilities in 14/15
```

Three chains carry almost all the value, and they are largely independent:
**11 → 30/31/32/33** (testing), **14 → 15** (fixtures), and
**16 → 17 → 21 → 27** (audio). The synchronization chain (23–26) depends on M5
and gates the realtime WLED work. Starting all four at once is the main
sequencing risk; entry 11 is the cheapest and unblocks the most.
