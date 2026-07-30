# Show-Control Implementation Roadmap

**Status of this document:** PROPOSED. Established on branch
`docs/lighting-audio-show-control-architecture` against HEAD `bc91b77`.

Phases 1–5 describe how the show-control capability in
[show_control_architecture.md](show_control_architecture.md) would be built.
**No phase has started.** Phase numbering is a dependency order, not a priority
order, and carries no dates, no effort estimates, and no completion percentages
(decision D-10).

## Relationship to the existing roadmap

This document does **not** replace [roadmap.md](roadmap.md). The two track
different things and both apply:

- **[roadmap.md](roadmap.md) milestones M0–M12** stabilize the application that
  exists — safe import, tests, atomic storage, runtime state, validation,
  security, fixture profiles. They address the verified defects in
  [audit_findings.md](audit_findings.md).
- **The phases here** add a capability that does not exist. Every one of them
  depends on milestones from that list.

```text
STABILIZATION (roadmap.md)              CAPABILITY (this document)
──────────────────────────              ──────────────────────────
M0  documentation ─────────────────────► (this document)
M1  safe import ───────┐
M2  tests + seams ─────┼───────────────► Phase 1  architecture + simulation
M3  atomic storage ────┼──┐
M5  runtime + pacing ──┼──┼────────────► Phase 2  baseline hardware control
                       │  └────────────► Phase 3  audio analysis
M7  LedFx config ──────┘
M8  validation ────────┬───────────────► Phase 4  advanced fixtures
M9  security ──────────┘
M10 fixture profiles ──────────────────► (Phase 4 consumes it)
M5  pacing (again) ────────────────────► Phase 5  synchronization + editing
```

**Milestone M10 and Phase 4 are the same work seen from two angles.** M10
replaces hardcoded fixture knowledge with data; Phase 4 uses that data to
support Keobin, GigBAR, lasers, and haze. They should be executed as one
programme, not duplicated. Where this document and M10 disagree, M10 governs the
schema and this document governs the fixture-specific requirements.

**Phase numbering versus milestone numbering.** Phases are numbered
independently and deliberately — merging them into the M-series would have
required renumbering milestones while OQ-1 (the M0–M12 versus M0–M10 question)
is still open. If OQ-1 resolves toward renumbering, these phases are unaffected.

---

# Phase 1 — Architecture and simulation

**Hardware-free in its entirety.** Nothing in this phase touches a fixture, and
nothing in it should require the rig.

## Prerequisites

| Prerequisite | Why it blocks |
| --- | --- |
| **M1** — safe import | `SENDER` is constructed at import (F3); no transport can be injected until that is fixed |
| **M2** — test seams and pytest baseline | There is no test suite (F10); simulation output with nothing asserting over it is not validation |
| **M3** — typed read outcomes | Schemas need to distinguish missing from corrupt before artifacts depend on them |
| Decision on **PD-1** (semantic boundary) | It determines the shape of every schema in this phase |

## Deliverables

1. **Schemas** — `AudioFeatureTimeline`, `ShowTimeline`, `Cue`,
   `FixtureDefinition`, `FixtureInstance`. Pydantic, versioned from the first
   commit, validated on read.
2. **Transport interfaces** — `DmxTransport`, `WledStateTransport`,
   `WledPixelTransport`, each with a null implementation, modelled on the
   existing `PointSink`/`NullSink` pattern (`backend/ilda/sink.py`).
3. **Recording DMX transport** — appends `(show_time, universe, 512-byte frame)`
   records to a file that both tests and the future visualizer read.
4. **Semantic cue model and capability vocabulary** — small, deliberately
   constrained, covering only what the current rig has.
5. **Fixture profiles for the existing rig**, derived from manuals, carrying
   `verified: false`.
6. **Address-collision and universe-bounds validation.**
7. **The audio artifact format** — schema and cache-key design only. No
   extraction yet.
8. **Full-song simulation harness** — runs a timeline against null and recording
   transports and produces a frame log.
9. **Characterization frames for the current rig** — the byte-exact 512-byte
   universe frame each stored device preset produces today, under the existing
   `MAPPER` concatenation. These are the regression oracle for Phase 2's
   addressing migration.

## Validation requirements

- All hardware-free, on both Linux and Windows CI.
- Every schema round-trips and rejects malformed input explicitly.
- Simulation is deterministic: the same inputs produce an identical frame log.
- Characterization frames are captured **before** any change to `MAPPER`.
- No test can reach a real transport — asserted, not assumed.

## Risks

| Risk | Mitigation |
| --- | --- |
| Schema churn as understanding improves | Version from commit one; expect and plan for migrations |
| Over-designing the cue model before a generator exists | Start with the capabilities the current rig actually has, and nothing else |
| Capability vocabulary grows to accommodate one odd fixture | Prefer `macro_select` over a capability only one product understands |
| Characterization frames captured after a change | Capture them first; treat it as the phase's first task |

## Completion criteria

- A show timeline can be authored by hand, simulated end to end, and its frame
  log asserted against expectations — with no hardware present.
- Every existing rig fixture has a profile derived from its manual.
- Characterization frames exist for every stored device preset.
- Address-collision validation rejects a deliberately colliding patch.

## Likely user-facing improvement

**Almost none, and this should be said plainly.** Phase 1 is entirely
infrastructure. Its value is that Phases 2–5 become possible and reviewable. An
operator would notice nothing.

---

# Phase 2 — Baseline hardware control

**The first phase that touches the rig.** Native-Windows validation is required
throughout, under [platform_support.md](platform_support.md) and D-8.

## Prerequisites

| Prerequisite | Why it blocks |
| --- | --- |
| **Phase 1 complete** | Nothing to drive the transports with otherwise |
| **M5** — runtime state and pacing | F4, F5, F6: disk must leave the control path before output timing means anything |
| **M7** — LedFx host/port decoupling | F17 makes a second network destination inexpressible |
| **OQ-5 answered** | Which real installations must survive the addressing migration |
| Decision on **PD-8** | Whether WLED is addressed directly, through LedFx, or both |

## Deliverables

1. **WLED JSON state control** behind `WledStateTransport`.
2. **WLED WebSocket** state channel, replacing polling for WLED devices.
3. **One real DMX transport** behind the interface — the existing sACN sender,
   refactored to be injectable rather than a module-global.
4. **The addressing migration**, staged exactly as specified in
   [fixture_and_transport_strategy.md](fixture_and_transport_strategy.md)
   Part 3: derive implied addresses → add fields unused → switch the mapper →
   only then allow editing. Steps 3 and 4 in **separate commits**.
5. **One PAR profile** and **one light-bar profile**, verified against manuals
   and against the physical fixtures.
6. **Blackout and safe shutdown** on every transport — idempotent, callable at
   any time, independent of show-engine state.
7. **Physical output validation** against the rig.

## Validation requirements

- **The byte-identical invariant**: after the migration, every stored device
  preset produces the same 512-byte frame as the Phase 1 characterization
  captured. A single mismatch blocks the phase.
- Native Windows only for anything physical. No WSL2 result substitutes.
- Blackout verified to actually darken the rig, from a running show and from a
  crashed one.
- Ctrl+C and process shutdown release the sender cleanly.
- The relevant rows of the native-Windows checklist in
  [platform_support.md](platform_support.md) are exercised and marked.

## Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| The migration silently re-patches a working rig | **Highest in this document** | Byte-identical oracle; split commits; rig validation; OQ-5 first |
| A `verified: false` profile reaches physical output | High | Enforce the block in code, not documentation |
| The `sacn` monkey-patch hides transport errors | Moderate | `backend/dmx/sender.py:19-30` swallows `OSError`; revisit when the transport becomes injectable — an invisible error cannot be responded to |
| WLED direct control conflicts with concurrent LedFx control of the same device | Moderate | PD-8 must settle ownership per device, not per capability |
| Regressing working sACN output while refactoring it | Moderate | Characterization tests cover the sender, not just the mapper |

## Completion criteria

- A hand-authored timeline drives real PARs, a real light bar, and real WLED
  devices.
- The migration is complete with the byte-identical invariant proven.
- Blackout works from every state, including after a simulated crash.
- The checklist rows for this phase are marked on native Windows.

## Likely user-facing improvement

**The first real one.** Direct WLED control without pre-authoring every
behaviour as a LedFx scene; fixtures addressable rather than positional; a
blackout that works. Timing is not yet improved — that is Phase 5.

---

# Phase 3 — Audio analysis

**Hardware-free.** This phase is entirely offline and is the one most amenable
to WSL2 development.

## Prerequisites

| Prerequisite | Why it blocks |
| --- | --- |
| **M3** — atomic writes | F7 + F8: a truncated artifact would be read back as "no beats detected" |
| **Phase 1** artifact schema | Extraction needs a destination |
| **FFmpeg packaging decision** | External binary; the Windows executable must locate or bundle it, and bundling is a redistribution question |
| Decision on **PD-10** | Whether generated shows are wanted determines how much generator to build |

## Deliverables

1. **FFmpeg decode and normalization** — subprocess-invoked, canonical mono
   float PCM at the project sample rate, applied gain recorded, explicit failure
   on undecodable input.
2. **Librosa extraction** — beats, downbeats, onsets, tempo, loudness, named
   frequency bands, spectral centroid, harmonic/percussive split, sections,
   silence — each versioned and independently testable.
3. **Confidence values** on every event class.
4. **The artifact cache**, keyed by content hash + extractor version + config
   hash, written atomically under `LIGHTSAPP_DATA_DIR`.
5. **Manual override structure**, stored separately from generated values.
6. **Deterministic show generation** from artifact + style + fixture groups +
   intensity profile, producing a `ShowTimeline`.
7. **Cue conflict resolution** — priority, manual-beats-generated, deterministic
   tie-breaking.
8. **An audio-file input path** in the application — the first one it has ever
   had.

## Validation requirements

- **Determinism**: two runs over the same input produce byte-identical
  artifacts.
- **Cross-platform determinism measured, not assumed** — Linux and Windows
  compared explicitly, and any floating-point divergence documented rather than
  waved away.
- Regeneration from the same inputs produces an identical `ShowTimeline`.
- Manual overrides survive re-analysis.
- Cache invalidation verified for each of the three key components
  independently.
- Generated shows validate against the safety rules: no haze on beat-level
  features (PD-9), no laser cues without a modelled gate.

## Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Downbeat and section detection unreliable for the actual music | High | Confidence-gated mappings; manual correction (deliverable 5) as a first-class path, not an afterthought |
| FFmpeg packaging blocks the Windows build | High | Resolve before Phase 3 starts; it is a licence question as well as a technical one |
| Analysis dependency tree bloats the packaged executable | Moderate | Measure early; consider whether analysis must ship at all, or is a development-host activity |
| Overrides silently discarded on re-analysis | Moderate | Separate storage is a schema requirement, not a UI convenience |
| Essentia adopted before the licence question is answered | **Blocking if it happens** | Not in this phase. Defer until the baseline proves it is needed |

## Completion criteria

- An audio file can be supplied, analyzed, cached, and regenerated
  deterministically.
- A show generated from it simulates end to end (Phase 1 harness) and asserts
  clean.
- Manual corrections survive an extractor version bump, or the system reports
  honestly that they cannot be re-applied.

## Likely user-facing improvement

**Substantial, and the first that changes what Lights is for.** Supply a track,
get a show that is aligned to its structure rather than to onset count. Timing
accuracy is still limited by Phase 5's absence, but structural awareness —
sections, buildups, restraint in quiet passages — is entirely new.

---

# Phase 4 — Advanced fixtures

**Safety-critical.** [laser_and_haze_safety.md](laser_and_haze_safety.md) is
required reading before any work in this phase begins, and it is normative, not
advisory.

## Prerequisites

| Prerequisite | Why it blocks |
| --- | --- |
| **M8** — validation and preflight | Profiles must be validated before output is enabled |
| **M9** — security | The laser-enable endpoint must not be callable by anything that can reach the port (F12, F13) |
| **M10** — fixture profiles | This phase is M10's consumer; they are one programme |
| **PD-4 resolved** | The laser gate must cover the **DMX** path, which M11 does not address |
| Phase 2 complete | Real transports and verified profiles must exist first |
| Exact manufacturer manuals | For every Keobin and GigBAR model and mode in the rig |

## Deliverables

1. **Keobin support** — profiled from the manual for the exact model, modelled
   as several logical fixtures over one address block so the laser sections sit
   behind the gate rather than inside a general profile.
2. **Exact GigBAR model and mode support** — same composite modelling; PARs and
   derbies reuse the shared renderers.
3. **The laser gate**, in full: master enable defaulting off on every start,
   per-session manual confirmation, gating at both renderer and transport,
   startup blackout, disconnect blackout, duration limits with an independent
   watchdog, unknown-channel fail-closed, test mode excluding emission, audit
   logging, emergency blackout.
4. **Haze support** with warm-up tracking, output/fan separation where the
   machine provides it, maximum duty cycle enforced **at generation time**,
   minimum off period, early cue scheduling with a venue lead time, cooldown,
   and disconnect-to-off.
5. **Generator enforcement of PD-9** — a style mapping haze to beat- or
   onset-level features fails validation.

## Validation requirements

- Every profile verified against the manual **and** against the physical
  fixture, on native Windows.
- The laser gate verified by attempting to emit through every path and
  confirming refusal — including from a generated cue, a manual override, and a
  high-priority cue.
- Duty-cycle and minimum-off enforcement verified in simulation before any
  physical haze.
- Emergency blackout verified from a running show, a stalled scheduler, and a
  crashed process.
- Watchdog verified by deliberately stalling the show engine.
- Audit log verified to survive an abrupt termination.

## Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Laser emission from an unverified or wrong profile | **Safety-critical** | `verified: false` blocks physical output; gate is independent of profile correctness |
| The gate implemented partially | **Safety-critical** | It is specified as a set; a subset produces a system that appears gated and is not |
| Haze mapped to beats through a style | High | PD-9 enforced in the generator, not just documented |
| Fire-alarm activation from haze | High | Venue policy and detection state confirmed by the operator before use; duty-cycle limits reduce but do not eliminate the risk |
| Wrong GigBAR generation assumed | High | Exact model and mode recorded in the profile `source` field; no generic GigBAR profile |
| M11's ILDA scope mistaken for covering DMX lasers | High | PD-4 exists precisely because it does not |

## Completion criteria

- Keobin and the exact GigBAR model operate from verified profiles.
- Every laser control in the safety document is implemented and individually
  verified.
- Haze operates under enforced duty-cycle and minimum-off rules.
- The relevant native-Windows checklist rows are marked.
- A `lights-dmx-safety-audit` equivalent review has passed on the branch.

## Likely user-facing improvement

**High, and the highest-risk.** The full rig becomes controllable from a show
timeline. This is also the phase where a mistake damages equipment or harms
someone, which is why its prerequisite list is the longest in the document.

---

# Phase 5 — Advanced synchronization and editing

## Prerequisites

| Prerequisite | Why it blocks |
| --- | --- |
| **M5** — pacing and runtime state | Synchronization on a disk-polling control bus measures disk behaviour |
| **OQ-6 answered** | The target DMX refresh rate, measured on the rig |
| **PD-7 decided** | Whether authoritative show time comes from browser or backend playback |
| Phases 2 and 3 complete | Nothing to synchronize otherwise |

## Deliverables

1. **Monotonic playback clock**, with audio position as authoritative show time
   and drift measured and corrected.
2. **Lookahead scheduler** — priority queue, configurable horizon, dispatch at
   `cue.t − latency[device]`, with an explicit invalidation path on seek.
3. **Per-device latency calibration** — measured on the rig, stored on the
   fixture instance.
4. **Fixed-rate DMX rendering** at the OQ-6 rate; WLED pixel output on its own
   tick.
5. **WLED realtime UDP/DDP pixel transport.**
6. **Improved section and downbeat detection**, including the deferred **Essentia
   evaluation** — behind the extractor interface, and **only after its licence
   question is resolved**.
7. **Manual timeline editing** — cue edits stored separately and surviving
   regeneration.
8. **Waveform and cue visualization**, built on the machine-readable diagnostics
   the recording transport already produces.
9. **Show templates** — reusable style, group, and intensity configurations.

## Validation requirements

- Timing accuracy measured against the rig on native Windows — the only
  environment where the measurement means anything (D-8).
- Drift measured over a full track, not a short sample.
- Latency compensation verified per device class, including the very different
  haze lead time.
- Seek, pause, and resume verified not to leave stale dispatched cues.
- Manual edits verified to survive regeneration.
- WLED realtime throughput measured at realistic pixel counts.

## Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Browser-based playback position adds unbounded network jitter | High | PD-7; if browser playback wins, the jitter budget must be measured before the scheduler is designed around it |
| Lookahead horizon makes seeking awkward | Moderate | Explicit invalidation; treat seek as a first-class operation from the start |
| WLED realtime saturates the network at high pixel counts | Moderate | Measure early; rate-limit per device |
| Essentia adopted before the AGPL question is resolved | **Blocking if it happens** | Licence decision precedes the evaluation branch |
| The timeline editor expands without bound | Moderate | Diagnostics view and editor are separate deliverables; the frontend has no build step, which is a real constraint on editor scope |

## Completion criteria

- Cues land within a measured, documented tolerance on the rig.
- Drift is bounded over a full track.
- The operator can correct a mis-detected downbeat and see the show change.
- WLED pixel effects run synchronized with DMX output.

## Likely user-facing improvement

**Transformative.** This is the phase where the system stops being "lights that
react" and becomes "a show that is synchronized". Everything before it builds
the machinery; this is where the machinery is aimed.

---

# Cross-phase notes

## What must never be compromised, in any phase

1. **The semantic boundary** (PD-1). No channel numbers above the fixture layer.
2. **Fail closed** for unknown fixtures, modes, and capabilities.
3. **Hardware-free by default.** Every phase's work is developed and tested
   without the rig; the rig confirms, it does not develop.
4. **No WSL2 result is HARDWARE VERIFIED** (D-8). Not once, not for a small
   thing.
5. **The laser gate is not priority-resolvable.** Creative mechanisms and safety
   mechanisms do not share a code path.
6. **Haze is never beat-mapped** (PD-9).

## Where this roadmap could be wrong

Recorded honestly, because it is a plan and plans are hypotheses:

- **If PD-10 resolves toward "better manual authoring, not generation"**, Phase 3
  shrinks to analysis-plus-alignment and Phase 5's editor moves much earlier.
  The audio layer is needed either way; the generator may not be.
- **If PD-8 resolves toward "LedFx only"**, entries for direct WLED control and
  realtime pixel output leave Phases 2 and 5 entirely, and the WLED story stops
  at scene selection.
- **If OQ-5 reveals installations that cannot be migrated safely**, the
  addressing migration in Phase 2 may need a compatibility mode, which changes
  its shape substantially.
- **If the packaged-executable licence review blocks FFmpeg bundling**, audio
  analysis may become a development-host activity that produces artifacts
  shipped alongside shows, rather than a feature of the distributed application.
  That is a significant change to Phase 3's deliverable, and it should be
  checked early rather than discovered at packaging time.
