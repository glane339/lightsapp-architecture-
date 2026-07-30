# Live Show-Control Implementation Roadmap

**Status of this document:** TARGET ARCHITECTURE delivery sequence; all
deliverables are planned work unless explicitly labeled current behavior. Updated on branch
`docs/live-renderer-architecture`.

This roadmap delivers the capability described in the canonical
[live show-control architecture](show_control_architecture.md). No phase has
started. Phase ordering expresses dependencies, not dates, effort, or
completion percentages.

## Relationship to the stabilization roadmap

[roadmap.md](roadmap.md) remains the dependency-ordered plan for stabilizing the
current application. This document adds live analyzer and renderer capability.
The two plans share work and must not implement it twice:

- M1 and M2 make import safe and add hardware-free seams.
- M3 makes durable artifacts safe to write and explicit to read.
- M5 removes JSON from the live DMX path and adds pacing.
- M7 repairs the LedFx integration boundary.
- M8 adds validation and preflight.
- M9 establishes operator-access policy.
- M10 supplies fixture profiles and explicit patches.
- M11 governs safe physical ILDA output.

The live programme preserves those foundations. It does not bypass them to
reach audio reactivity sooner.

**Ownership rule:** Phase 1 defines and simulates the fixture-profile schema.
M10 owns production fixture profiles, migration from hardcoded fixture
knowledge, and the explicit patch data for real installations. Later
show-control phases consume and commission those profiles; they do not create a
second profile system.

---

# Phase 1 — Schemas, semantic boundaries, and simulation

**Hardware-free.**

## Prerequisites

- M1 safe import;
- M2 pytest baseline and injectable output seams;
- M3 typed storage outcomes for durable schemas;
- accepted semantic-cue and replay decisions in
  [decisions.md](decisions.md).

## Deliverables

1. Versioned conceptual schemas for normalized feature frames, musical-state
   snapshots, semantic cues, fixture definitions, and fixture instances.
2. A deliberately small semantic cue and capability vocabulary based on the
   current rig.
3. Versioned fixture-profile and patch schemas plus synthetic test fixtures.
   Production profiles and migration belong to M10.
4. Explicit universe and 1-based start-address fields plus collision and bounds
   validation.
5. Null and recording transports for DMX and both WLED output modes, following
   the existing ILDA `PointSink`/`NullSink` precedent.
6. A deterministic simulation pipeline that can replay authored feature,
   state, and cue logs into recorded WLED and complete DMX universe output.
7. Characterization frames for every current device preset before positional
   addressing changes.
8. Initial safety-policy types for blackout, laser master enable, strobe
   limits, intensity ceilings, atmosphere limits, manual override, freeze or
   hold, and loss of signal.

## Validation

- No test can reach a real output transport.
- Every schema round-trips and rejects malformed data explicitly.
- Identical inputs produce identical state, cue, and output logs.
- Characterization frames are captured before `MAPPER` changes.
- A deliberately colliding fixture patch is rejected.
- Laser, strobe, and atmosphere policy cannot be bypassed by cue priority.

## Completion boundary

A hand-authored normalized feature log can run through state, cue, and fixture
rendering into recording transports without hardware. This phase does not add
live audio capture or production output.

---

# Phase 2 — Safe fixture and transport foundation

**First phase that may touch the rig. Native-Windows validation is required.**

## Prerequisites

- Phase 1;
- M5 in-memory runtime state and output pacing;
- M7 configured, injectable LedFx client;
- M8 validation and preflight;
- M10 production fixture profiles and explicit patch migration;
- OQ-5 migration scope answered.

## Deliverables

1. Existing sACN output behind an injectable `DmxTransport`.
2. Output integration for the explicit patch data migrated by M10, checked
   against Phase 1 characterization frames.
3. Complete-universe frame rendering from explicit patches.
4. Native-Windows commissioning of one PAR profile and one bar profile supplied
   by M10, including manual and physical verification.
5. Idempotent blackout and safe shutdown on every transport.
6. A LedFx compatibility adapter with independent host and port, timeouts, and
   defined failure behavior.
7. Explicit per-device ownership so LedFx and native output cannot fight for
   the same WLED device.

## Validation

- Current presets produce byte-identical DMX frames after the addressing
  migration.
- Real output is exercised only on native Windows.
- Blackout is verified from normal playback and simulated failure states.
- Sender shutdown, disconnect diagnostics, and loss-of-signal behavior are
  observed on the real deployment path.
- An unverified fixture profile is blocked from physical output.

## Completion boundary

The current rig can still run through LedFx and sACN behind safe, testable
boundaries. This phase establishes migration infrastructure; it does not yet
provide the new live analyzer or native WLED effects.

---

# Phase 3A — Real-time party analyzer

**Primary use-case phase. Live-first and hardware-free until output is connected
through the earlier recording seams.**

## Prerequisites

- Phase 1 normalized schemas and replay logs;
- M2 hardware-safe test environment;
- source lifecycle ownership from M1/M5;
- a measured capture-host prototype before an operating-system API is selected
  permanently.

## Deliverables

1. Source-independent audio boundary.
2. Preferred system-audio capture on the supported show host, with the
   platform-specific API kept behind that boundary.
3. Microphone fallback.
4. Deterministic synthetic sources and recorded capture replay.
5. Normalized feature stream with timestamp, relative loudness, bass/mid/treble
   energy, brightness, onset strength, beat probability, estimated tempo, beat
   phase, and confidence.
6. Live musical-state estimates such as quiet, groove, building, peak,
   breakdown, transition, and unknown.
7. Smoothing, hysteresis, confidence thresholds, and transition rules.
8. Track/source-transition handling for silence, pause, abrupt tempo or
   spectral change, manual skip, optional metadata track change, and capture
   loss/recovery.
9. Gradual reset behavior for tempo history, beat phase, bar counter, rolling
   normalization, and effect progression.
10. Recording of audio or normalized features for deterministic replay.

## Initial performance budgets

- audio chunks around 10–20 ms;
- feature updates around 50–100 Hz;
- musical-state updates around 20–50 Hz;
- end-to-end visible response under approximately 80 ms;
- bounded latest-state-wins queues;
- stale frames skipped rather than accumulated.

These are nonbinding targets. Measure stage latency and dropped frames on the
actual supported host.

## Validation corpus

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

## Completion boundary

A live system-audio source can produce stable, replayable musical-state and
semantic-cue logs with microphone fallback. It is not complete merely because
one capture API works on one developer machine; source failure, transition
behavior, latency, and replay must also be measured.

---

# Phase 3B — Optional offline track analysis

**Prepared-track enhancement. Not a prerequisite for ordinary party mode.**

## Prerequisites

- Phase 3A shared feature vocabulary;
- M3 atomic persistence;
- explicit packaging and license decisions for any decoder or analyzer;
- a defined relationship between track identity and cached artifacts.

## Deliverables

1. Audio-file decoding into the same normalized feature vocabulary.
2. Cached feature timelines keyed by content identity, analyzer version, and
   analysis configuration.
3. Prepared shows and known-track lookup.
4. Optional future-aware annotations such as structural boundaries and silence.
5. Manual corrections stored separately from generated analysis.
6. Graceful fallback to live analysis when a file or cache is unavailable,
   unknown, invalid, or stale.

## Validation

- Repeated analysis is deterministic within defined numerical tolerances.
- Cache invalidation is exercised for content, version, and configuration
  changes.
- Manual corrections survive re-analysis or fail with an explicit explanation.
- A cached timeline and a live replay use compatible downstream state and cue
  logic.
- Absence of offline analysis never prevents live party mode from starting.

## Completion boundary

A prepared or known track can reuse cached analysis and manual corrections
without creating a second cue engine. The application still treats live capture
as the runtime source of truth during unprepared playback.

---

# Phase 3C — Native renderer

**Incremental replacement path. LedFx remains available during migration.**

## Prerequisites

- Phases 1 and 2;
- Phase 3A semantic cues;
- measured fixture and network behavior;
- exact fixture profiles for devices receiving physical output.

## Deliverables

1. Layer-based native WLED effects driven by semantic cues.
2. State-oriented WLED control for presets, brightness, segments, colors,
   palettes, and lower-rate changes.
3. Realtime pixel transport for custom effects using a protocol validated
   against supported hardware; DDP is a candidate, not a commitment.
4. Semantic DMX rendering into complete universes at a fixed rate.
5. Fixture renderers for PARs, bars, and composite multi-effect fixtures.
6. Styles and presets that configure semantic mappings without placing channel
   numbers above the fixture layer.
7. Independent WLED and DMX output loops using bounded latest-state-wins
   handoffs.
8. Safe frame dropping and diagnostics for missed deadlines.
9. LedFx parity comparisons for the existing scenes operators rely on.
10. Retained LedFx compatibility until native rendering is demonstrably
    reliable.

## Initial performance budgets

- native WLED rendering around 30–60 frames per second;
- DMX output around 30–44 frames per second;
- capture-to-visible response under approximately 80 ms.

The rates are measured budgets, not hardcoded guarantees. Actual WLED firmware,
pixel counts, network load, DMX node behavior, and fixture response determine
supported settings.

## Validation

- The same semantic cue log can drive LedFx compatibility, native WLED, and DMX
  recording paths for comparison.
- Direct and LedFx ownership cannot overlap on one WLED device.
- Pixel streaming never uses the low-rate state path.
- DMX output uses explicit universe/start-address patches and complete frames.
- Missed frames are skipped, not replayed late.
- Emergency blackout, laser gating, strobe limits, intensity ceilings,
  atmosphere limits, freeze/hold, manual override, and loss-of-signal policy
  are exercised before physical rollout.

## Completion boundary

Native rendering is demonstrably reliable on supported devices, has measured
performance, and has explicit parity results. LedFx removal is not required for
completion and is a separate later decision.

---

# Phase 4 — Advanced fixtures and safety policy

**Safety-critical.**

## Prerequisites

- Phase 3C fixture-aware renderer;
- M8 preflight;
- M9 operator-access policy;
- M10 fixture profiles;
- exact manufacturer manuals;
- the full policy in [laser_and_haze_safety.md](laser_and_haze_safety.md).

## Deliverables

1. Renderer integration and native-Windows commissioning for exact-model
   Keobin and GigBAR-family composite profiles supplied by M10; no second
   profile schema or migration path.
2. Laser master enable defaulting off, deliberate per-session confirmation,
   renderer and transport gates, startup/disconnect blackout, duration limits,
   watchdog, audit log, and non-emitting test mode.
3. Strobe limits and intensity ceilings enforced after creative priorities.
4. Haze warm-up, separate output/fan capabilities where applicable,
   duty-cycle and minimum-off policy, rate limiting, cooldown, manual override,
   and disconnect-to-off.
5. Safe freeze/hold and loss-of-signal transitions.
6. Emergency blackout independent of the audio, cue, and ordinary render
   pipelines.

## Validation

- Simulate every safety policy with null and recording transports first.
- Verify profiles against manuals and physical fixtures on native Windows.
- Attempt to bypass gates through generated, manual, and high-priority cues.
- Stall capture, state estimation, cue generation, and rendering separately.
- Confirm software controls do not get documented as legal or venue-compliance
  guarantees.

---

# Phase 5 — Calibration, diagnostics, and authoring

## Prerequisites

- Phases 3A and 3C;
- a stable recording format;
- measured hardware timing.

## Deliverables

1. Per-device latency calibration and long-run drift diagnostics.
2. Visual inspection tooling built from machine-readable feature, state, cue,
   WLED, and DMX logs.
3. Manual cue and prepared-track correction workflows.
4. Reusable styles, fixture groups, and intensity profiles.
5. Operational dashboards for capture health, queue depth, dropped frames,
   transport state, and active safety policy.

The diagnostic format precedes any editor. A full frontend timeline editor is
optional and must be scoped separately.

---

# Subsequent documentation/tooling increment — Mermaid

Mermaid diagrams may be added after this branch as a dedicated documentation or
tooling increment. That work should translate the approved text architecture;
it must not silently decide unresolved schemas, transports, algorithms, or
ownership. No Mermaid diagram or dependency is part of
`docs/live-renderer-architecture`.

---

# Cross-phase rules

1. Live capture is party mode's runtime source of truth.
2. Spotify metadata is optional enhancement, not raw audio.
3. Offline analysis is optional and uses the shared feature vocabulary.
4. No channel numbers cross the semantic cue boundary.
5. Fixture addressing is explicit.
6. LedFx remains a compatibility adapter until native rendering is proven.
7. Unknown fixtures and modes fail closed.
8. Safety policy is not priority-resolvable.
9. Hardware-free replay is the primary regression mechanism.
10. WSL2 results never earn HARDWARE VERIFIED status.
11. Python remains primary until profiling demonstrates a native-code need.
