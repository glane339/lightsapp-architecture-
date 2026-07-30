# Decisions and Open Questions

**Status of this document:** canonical. Accepted decisions are binding on
future work in this repository. Open questions require an owner decision and
must not be resolved by an agent acting alone.

Decisions are numbered `D-n`; open questions `OQ-n`; **proposed** decisions
`PD-n`. None is renumbered once assigned.

`D-n` decisions are accepted and binding. `PD-n` decisions are **not accepted**
and bind nothing — they are recommendations awaiting an owner. On acceptance a
`PD-n` is restated as the next free `D-n`, and the `PD-n` entry records where it
went.

---

## Accepted decisions

### D-1 — Incremental stabilization, not a rewrite

The codebase is small, coherent, and has a real domain model. It is stabilized
in dependency order rather than replaced.

*Why:* a rewrite discards the prototype's most valuable asset — a device preset
→ combined preset → scene → full scene → active show workflow that is
implemented end to end and coherent in code — in exchange for risk. (Whether
that workflow is usable for real shows is CODE-INSPECTED ONLY; no repository
evidence establishes real-show use.) The defects in
[audit_findings.md](audit_findings.md) are individually addressable.

### D-2 — Hardware is assumed unavailable

All development, inspection, and validation assumes no DMX, sACN, LedFx, ILDA,
or laser hardware is present. Fake, null, simulated, or injected adapters are
preferred everywhere.

*Why:* the repository's primary environment is WSL2, which cannot verify
hardware behavior, and accidental output to a real rig is not a recoverable
mistake.

### D-3 — `backend/main.py` is never imported or run for validation

*Why:* F1, F2, and F3 — importing it initializes data, starts sACN, and calls
`uvicorn.run`. This restriction lifts only when M1 is complete and verified.

### D-4 — Persistent JSON storage is retained

JSON files remain the persistence format. Atomicity, typed errors, and
validation are added around them (M3, M8). No database migration is planned.

*Why:* the data volumes are tiny, the files are human-inspectable and
hand-editable during a show, and the format is not the cause of any P0 finding.
F7 and F8 are defects in *how* JSON is written and read, not in the choice of
JSON.

### D-5 — Persistence stops being the control bus

Runtime state moves into memory (M5). Persistence continues to exist for
durable configuration but is removed from the high-frequency output path.

*Why:* F6. Using `devices.json` as inter-thread IPC is the cause of the
continuous re-parsing and of the output path's exposure to partially written
files. It is *not* the cause of the unpaced loop — F4 is an independent defect,
the absence of any application-level wait in the loop body. M5 fixes both,
because fixing either alone leaves the other in place.

### D-6 — ILDA output remains nonphysical until the M11 safety architecture exists

`LoggingSink` stays in place. A DAC adapter is added only behind a validated
library root, buffered output, watchdog, interlock, emergency stop, safe
shutdown, output-disabled-by-default, and native-Windows hardware testing.

*Why:* the current inability to emit laser output is a safety property. It is
given up deliberately and only once, with the full safety architecture in place
— never as a side effect of another change.

### D-7 — The deleted reinforcement-learning system is not restored

`stable-baselines3` and `gymnasium` stay out. Intelligent scene selection
proceeds rules-first (M12).

*Why:* F24 — the dependencies carry a large footprint and a transitive PyTorch
burden with no working code path, and no evidence has been presented that scene
selection requires reinforcement learning. Deterministic rules are testable
without hardware; a learned policy is not.

### D-8 — WSL2 develops, native Windows validates

No HARDWARE VERIFIED claim may originate from a WSL2 result. See
[platform_support.md](platform_support.md).

*Why:* WSL2's virtual network adapter, advisory file locking, and absent
Windows firewall make its results non-transferable for exactly the behaviors
that matter for a lighting rig.

### D-9 — The existing browser microphone path is preserved during migration

The current microphone capture and onset detector are not removed merely to
begin the live-renderer migration. They remain available until the replacement
source boundary and microphone fallback are working and verified.

*Why:* it is the only supported audio-reactive path that currently exists, and
incremental stabilization remains binding under D-1. Its browser placement,
raw-FFT vocabulary, and per-onset HTTP advancement are not binding on the
future analyzer. D-13 and D-14 supersede D-9 only where it previously implied
that browser microphone analysis was the permanent primary architecture.

### D-10 — Evidence labels are mandatory

Every substantive claim in this documentation set carries one of the labels
defined in [project_overview.md](project_overview.md). Completion percentages
are prohibited.

*Why:* the specific failure this guards against is a future reader mistaking
`ShowCatalog`, `RuntimeManager`, adapters, preflight, or atomic persistence for
implemented components. The existing documentation avoided that trap (F25) and
this set must not reintroduce it.

### D-11 — Stale documents are marked, not deleted

Superseded documentation gets a status banner identifying what is still
accurate and what replaced it.

*Why:* `RUN.md`, `QUICK_START.md`, and `BUILD_INSTRUCTIONS.md` contain
operational Windows knowledge that exists nowhere else in the repository. Their
inaccuracies are specific and can be flagged in place.

### D-12 — The first implementation branch is `architecture/safe-import-boundary`

Narrowly scoped to M1. See [current_sprint.md](current_sprint.md).

*Why:* nothing else can be tested until import is side-effect free, and a
narrow first branch establishes the review pattern for the milestones that
follow.

### D-13 — Party mode is live-first

Unpredictable, continuously changing Spotify playback is the primary use case.
Live audio capture is the runtime source of truth. Spotify metadata is an
optional identity and track-change enhancement, and offline analysis is an
optional prepared-track capability.

*Why:* Lights usually will not possess the original audio file before playback,
and a queue entry may change or be skipped without warning. Requiring complete-
file analysis would make ordinary party mode unavailable precisely when it is
most needed. Spotify metadata does not replace the program signal, and this
decision does not assume metadata APIs expose arbitrary raw audio.

*Supersedes:* PD-6's ordering of offline analysis as primary and microphone as
fallback. It does not reject offline analysis; it changes its role.

### D-14 — System-audio loopback is preferred over microphone for party mode

The future source boundary prefers real-time system-audio loopback on supported
show hosts. Microphone capture is the fallback. Platform-specific mechanisms
such as WASAPI remain implementations behind a source-independent interface,
not permanent architectural dependencies.

*Why:* loopback observes the program signal without crowd noise, room
reflections, or microphone placement. A microphone is still necessary when
loopback is unavailable or inappropriate. The source abstraction also supports
decoded files, deterministic signals, and recorded replay.

### D-15 — Live and offline analysis share one normalized feature vocabulary

System loopback, microphone, audio files, deterministic signals, and recorded
replay produce compatible timestamped feature frames. The conceptual
vocabulary includes relative loudness, named frequency-band energy,
brightness, onset strength, beat probability, tempo, beat phase, and
confidence.

*Why:* musical-state estimation and cue generation should not branch on the
source. A shared vocabulary makes live and prepared modes comparable and lets
recorded captures test the same downstream pipeline. Exact schemas, units,
windows, and algorithms remain future versioned implementation decisions.

### D-16 — Semantic cues are separate from physical channel values

Musical interpretation emits intent such as pulse washes, trigger a pixel
chase, accent bars, raise intensity, inhibit laser output, or adjust atmosphere
within policy. Universe, address, channel, DMX value, WLED packet, and LedFx
payload appear only below the fixture-rendering boundary.

*Why:* the boundary lets one analyzer coordinate LedFx, native WLED, and DMX;
lets fixture profiles change without rewriting musical logic; and provides a
single point for safety policy before physical output. Mapping an FFT bin
directly to a channel would collapse these properties.

*Accepts:* PD-1.

### D-17 — Native rendering is incremental and LedFx remains a compatibility adapter

Lights develops a custom live analyzer, semantic cue engine, native WLED
renderer, and fixture-aware DMX renderer incrementally. LedFx remains available
for existing WLED scenes until native rendering is demonstrably reliable and
parity has been evaluated.

State-oriented WLED control and realtime pixel streaming remain separate
responsibilities. DDP is a candidate realtime transport, not a locked
architecture choice; the transport must be validated against supported
hardware and performance.

*Why:* immediate LedFx removal would discard working scene behavior before its
replacement is proven. Explicit per-device ownership prevents LedFx and native
output from fighting for the same WLED device.

*Accepts and refines:* PD-8.

### D-18 — The live renderer is Python-first

Python is the primary language for audio analysis, cue orchestration,
scheduling, fixture rendering, transports, and backend integration. Rust or C++
may be introduced only behind a stable project-owned interface after profiling
on representative hardware demonstrates a bottleneck.

*Why:* the repository already uses Python, FastAPI, and Pydantic. A second
runtime would add packaging, testing, and integration cost before evidence
shows it is necessary. Profile-driven native optimization preserves the option
without pre-optimizing the architecture.

### D-19 — Deterministic capture and replay is the primary regression mechanism

The live pipeline is recordable at the audio/feature, musical-state, semantic
cue, WLED frame, and DMX universe boundaries. Recorded capture and deterministic
synthetic signals are first-class test inputs. Null and recording transports
must prevent physical output during regression tests.

*Why:* live audio and timing failures are otherwise difficult to reproduce, and
D-2 assumes hardware is unavailable during ordinary development. Boundary logs
isolate analyzer, estimator, cue, and renderer changes and let the same capture
be compared across versions.

*Accepts and expands:* PD-11.

### D-20 — Output safety policy is independent of creative priority

Emergency blackout, laser master enable, strobe limits, intensity ceilings,
haze or atmosphere limits, manual override, freeze or hold, and safe
loss-of-signal behavior are evaluated independently of creative cue priority.
The laser gate covers both ILDA and DMX-attached laser paths. Haze is never
mapped directly to beat- or onset-level features.

*Why:* a high-priority cue is still a creative request and cannot be permitted
to open a safety gate or bypass an operating limit. The current ILDA
non-emission property does not protect DMX-attached lasers. Atmosphere operates
at a much slower physical timescale than beats.

This is a software-control boundary, not a legal or venue-compliance guarantee.
It does not replace correct installation, physical interlocks or emergency
stops where appropriate, trained supervision, or operator responsibility.

*Accepts:* PD-4 and PD-9.

---

## Proposed decisions — show control

Entries in this section retain their stable `PD-n` identifiers. Some have now
been accepted or superseded by the clarified live-renderer decisions D-13
through D-20; their disposition is recorded in place. Entries still labeled
PROPOSED bind nothing until accepted as a `D-n`.

### PD-1 — Semantic cues remain independent of fixture channel mappings

**Accepted as D-16.**

A cue names *what should happen* and *to which fixture group*. It never carries
a universe, address, channel, or DMX value. Translation to channels happens only
in the rendering layer, from validated fixture profile data.

*Why:* it is the boundary that makes one audio analysis reusable across rigs and
one rig reusable across tracks, and it is what allows the entire show-generation
path to be tested with no fixture present. Violating it once collapses the
distinction permanently, because the first channel number in a cue makes every
later one look reasonable.

*Enforcement:* the `Cue` type should make the violation impossible rather than
merely discouraged, and generator review should reject it.

### PD-2 — Audio analysis remains independent of physical transports

**Accepted in substance by D-15 and D-16.**

The audio-analysis layer imports no fixture, transport, or cue type. It
produces normalized live feature frames or their offline timeline form and
nothing device-specific.

*Why:* live and offline analysis have different timing constraints, but both
remain independent of stateful, hardware-bound transports. Coupling them would
make analysis untestable without hardware, which under
[platform_support.md](platform_support.md) means untestable in the primary
development environment.

### PD-3 — Fixture profiles are versioned, validated, manual-sourced, and fail closed

Every profile records its manufacturer, exact model, mode, the manual reference
it was derived from, and a profile version. Every profile carries a `verified`
flag that is false until checked against the physical fixture. **Unverified
profiles may be simulated but may not receive physical output.** Unknown
fixtures, unknown modes, and undeclared capabilities produce no output and a
diagnostic — never a generic fallback or an approximation.

*Why:* F19 — fixture knowledge is currently hardcoded across four files, and the
only fixture-shaped data in the repository (`MODE_VALUES` in
`frontend/js/device_presets.js`) is unverified against any manual. A wrong
profile on a strobe or a laser section is not merely a visual defect.

### PD-4 — Laser and haze output are governed by dedicated safety policies, and the laser gate covers the DMX path

**Accepted as D-20.**

[laser_and_haze_safety.md](laser_and_haze_safety.md) is normative for all laser
and haze work. Critically, the laser gate applies to **DMX-attached laser
fixtures** — the Keobin lasers and the GigBAR laser section — and not only to
the ILDA DAC path.

*Why:* D-6 records that Lights cannot currently emit laser output, and that this
is a safety property surrendered only once, deliberately. **That property covers
the ILDA path only.** DMX laser channels are already reachable through the
existing sender with no gate of any kind. M11 addresses ILDA; nothing addresses
DMX. This gap must be closed before M10 exposes laser capabilities in fixture
profiles — and M10 sits *earlier* in the dependency order than M11.

The exact gate implementation and verified fixture-safe values remain future
work; the cross-output boundary is no longer open.

### PD-5 — Audio analysis results are cached, keyed by content hash, extractor version, and configuration hash

All three components, and manual corrections are stored separately from
generated values so that re-analysis preserves them.

*Why:* analysis is expensive enough that recomputation is not viable during
authoring, and the cache key is what makes generated shows reproducible.
Omitting any one key component produces stale artifacts that are very hard to
diagnose. Storing corrections inside the generated arrays silently destroys the
operator's work on the next re-analysis.

*Depends on:* M3. F7 plus F8 means a non-atomically written artifact would be
read back as "no beats detected" rather than as an error.

### PD-6 — Browser microphone reactivity is retained alongside offline analysis

**Superseded by D-13 and D-14.** The existing microphone path is still retained
under D-9, but live system-audio capture is primary and offline analysis is
optional.

The existing spectral-flux onset path in `frontend/js/home.js` stays during
migration. The future microphone source becomes a fallback to preferred system
loopback, and both live sources share the normalized feature vocabulary with
optional offline analysis.

*Why:* live operation needs no file and no preparation, which is exactly right
for an unpredictable party queue, a guest DJ, or a live band. The current
onset-count mechanism is not promoted into the new analyzer, but removing it
before its replacement works would violate D-1.

### PD-7 — One authoritative playback clock controls synchronization

A single monotonic time base coordinates live feature, state, cue, and render
timestamps. In live party mode, capture timestamps are authoritative. For
prepared playback, audio position may be authoritative show time.

**Remaining open sub-question:** where prepared-track playback happens. Browser
playback puts network jitter inside the timing budget; backend playback adds a
new audio-output responsibility. That question no longer blocks the live path.

*Needed:* a decision before prepared-track playback scheduling or Phase 5
authoring work depends on it.

### PD-8 — WLED state control and realtime pixel streaming are separate capabilities

**Accepted and refined by D-17.**

They use separate transports, separate rates, and separate failure semantics.
Pixel-rate updates never go through the JSON control path.

Lights will address WLED directly while retaining LedFx as a compatibility
adapter. The remaining implementation choices are the realtime protocol,
supported firmware/hardware matrix, parity criteria, and explicit ownership
transition for each device.

### PD-9 — Haze is a section-level control and is never mapped to beat- or onset-level features

**Accepted in substance by D-20.**

A style definition that maps `haze_output` to beats, onsets, or percussive
energy fails validation.

*Why:* haze does not respond on beat timescales, so the mapping produces no
visual effect; rapid cycling stresses the pump and heater; it defeats
duty-cycle and minimum-off accounting; and unpredictable bursts are the pattern
most likely to trip venue smoke detection. Documenting the prohibition is not
sufficient — the generator must enforce it.

### PD-10 — Show generation from audio is a goal

Live semantic cue generation is accepted by D-13 through D-17. This remaining
question is narrower: how much *offline prepared-show generation* the operator
wants versus manual authoring aided by cached analysis.

*Why this still needs an explicit answer:* Phase 3A's live cue engine is needed
either way, but Phase 3B's future-aware generator and Phase 5's editing surface
change substantially with the answer.

*Needed:* creator input. This is the single question with the largest effect on
the shape of the work.

### PD-11 — Physical output must support mock and recording transports

**Accepted and expanded by D-19.**

Every output path — DMX, WLED state, WLED pixels, ILDA — has a null
implementation and, where frames are meaningful, a recording implementation that
captures timestamped output instead of transmitting it.

*Why:* D-2 assumes hardware is unavailable and D-8 forbids hardware claims from
WSL2. Without recording transports there is no way to validate output at all in
the primary development environment. `backend/ilda/sink.py` already proves the
pattern works in this codebase; DMX and LedFx simply lack it.

### PD-12 — Transport libraries remain behind project-owned internal interfaces

No third-party transport library's types cross its integration boundary. The
internal interface is defined first; the library is evaluated against it.

*Why:* the existing LedFx integration is the counter-example. `LEDFXClient` is
constructed inline at its call site in `backend/routes/post.py`, which is a
direct cause of why F16 (inconsistent timeouts) and F17 (host coupling) are
awkward to fix and why the client cannot be substituted in a test. Repeating
that with a WLED client, an Art-Net library, or an audio library would multiply
the problem. Consistent with the existing constraint in
[architecture.md](architecture.md) Part 3 that adapters must not be forced into
one artificial shared interface — share lifecycle only.

---

## Open questions

These require an owner decision. An agent may present analysis but must not
decide unilaterally.

### OQ-1 — Milestone numbering: M0–M12 or M0–M10?

Two milestone sequences were specified in the same instruction set. This
documentation uses the finer-grained M0–M12 range (13 numbered milestones). The
mapping to the M0–M10 range (11 numbered milestones) is recorded in
[roadmap.md](roadmap.md). No work is dropped either way — only the granularity
and numbering differ.

*Needed:* confirmation of M0–M12, or an instruction to renumber.

**Nonblocking follow-up.** This does not gate M0's completion and does not
block M1 or any later milestone. If the owner chooses the M0–M10 range, the
change is a mechanical renumbering across these documents using the mapping in
[roadmap.md](roadmap.md).

### OQ-2 — Is the catalog one `ShowCatalog` or several repositories?

PROPOSED, unresolved. A single authoritative catalog is the stated direction,
but a facade over smaller per-aggregate repositories (devices, presets, scenes,
ILDA definitions, config) may be a better fit. Deciding early risks a God
object; deciding late risks scattered access patterns.

*Needed:* a decision before M3 hardens the storage interface.

### OQ-3 — Authentication mechanism and threat model

F12 and F13 are verified, but the correct remedy depends on facts not in the
repository: is the rig on a trusted private network, a venue network, or
occasionally the open internet? Options range from binding to localhost only,
through a shared operator token, to full authentication.

*Needed:* the actual deployment context, before M9.

### OQ-4 — Fixture profile format and source

M10 replaces hardcoded fixture knowledge with data. Undecided: whether to adopt
an existing format such as GDTF or Open Fixture Library, or define a minimal
project-specific schema.

*Needed:* a decision before M10 begins. Not urgent, but it shapes the schema.

### OQ-5 — Migration path for existing installations

M4 removes read-time fixture bootstrapping. Real installations may depend on
that behavior having already created their `gigbar`, `keobin`, and `haze`
entries. An explicit migration is required, and it must not damage a working
rig configuration.

*Needed:* confirmation of which real data directories exist and must survive,
before M4.

### OQ-6 — Target DMX refresh rate

Creator DESIGN INTENT indicates roughly 20 ms (about 50 Hz), while the approved
live-renderer architecture sets an initial nonbinding engineering budget of
approximately 30–44 FPS. Current code has no application-level pacing at all
(F4). The correct configurable default, and whether it should adapt to fixture
count, is unverified against real hardware.

*Needed:* a native-Windows measurement against the real rig, during M5.

### OQ-7 — Does the AI code get repaired or removed?

`backend/routes/ai_mode.py` and `frontend/html/ai_mode.html` remain, importing
a deleted package (F20, F23), alongside unused heavy dependencies (F24). Three
options: delete the orphaned code and dependencies; keep it as a placeholder
for M12; or rewrite it rules-first under M12.

*Needed:* a decision. Removing the unused dependencies is separable from the
question of the routes, and could be done earlier.

### OQ-8 — Scene `Sensitivity` and the audio-influence model

DESIGN INTENT describes a per-scene `Sensitivity` value and a "callable model
that is just a packet of information on how audio influences render". Neither
exists in code. It is UNKNOWN whether these remain wanted, and if so whether
they belong on `Scene`, on `Preset`, or in a separate audio-mapping object.

*Needed:* creator input, before M6 fixes the scene model's shape.
