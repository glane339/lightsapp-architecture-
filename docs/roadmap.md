# Roadmap

**Status of this document:** canonical. Milestones are TARGET ARCHITECTURE and
PROPOSED work, not implemented features. Finding references (`F1`, `F14`, …)
point at [audit_findings.md](audit_findings.md).

The ordering is a **dependency order, not a priority order**. A later milestone
is not less important; it is blocked by an earlier one. The clearest example:
authentication (M9) protects a system whose runtime behavior is still changing,
and it cannot be tested at all until M2 exists.

Milestones carry no dates, no effort estimates, and no completion percentages.
Progress is tracked by acceptance criteria in [current_sprint.md](current_sprint.md).

## Scope of this document

These milestones **stabilize the application that exists**. They address the
verified defects in [audit_findings.md](audit_findings.md).

A separate, PROPOSED programme adds show-control capability that does not exist
— audio-file analysis, semantic cues, fixture profiles as data, and synchronized
output. Its phases are in
[show_control_roadmap.md](show_control_roadmap.md), and every one of them
depends on milestones from this document. The two are complementary, not
alternatives. Note in particular that **M10 and that document's Phase 4 are the
same work seen from two angles** and should be executed once, not twice.

## Milestone numbering

An earlier draft of this plan used the M0–M10 range (11 numbered milestones).
This document uses the finer-grained M0–M12 range (13 numbered milestones),
which splits three items apart: read-time fixture mutation is separated from
atomic storage, validation and preflight is separated from LedFx configuration,
and security is separated from validation. The dependency order is otherwise
identical and no work was dropped.

**Owner confirmation requested, but nonblocking** — see
[decisions.md](decisions.md) OQ-1. Work proceeds under the M0–M12 range. If the
shorter range is preferred, the renumbering is mechanical: old M4→new M5, old
M5→new M6, old M6→new M7+M8, old M7→new M9, old M8→new M10, old M9→new M11, old
M10→new M12, with new M4 folded into old M3.

---

## M0 — Documentation and repository truth

**In progress.** This branch.

Consolidate current-state documentation, preserve audit findings, and establish
the distinction between current implementation, design intent, and target
architecture. Define the WSL2 / native-Windows policy.

*Done when:* a new contributor can determine what Lights does, how it works,
what is broken, and what is planned, without reading the source first — and can
tell verified behavior from aspiration in every claim.

## M1 — Safe import and lifecycle

*Blocks: everything. Nothing else can be tested until import is safe.*
*Addresses F1, F2, F3.*

- Import of the entry module produces no side effects.
- Storage initialization moves out of import time.
- Sender construction moves out of import time.
- `backend/routes/data.py` no longer creates directories at module scope.
- `uvicorn.run` is guarded by an explicit entrypoint.
- FastAPI lifespan owns startup and shutdown, including partial-startup
  cleanup.

## M2 — Hardware-safe tests and output seams

*Depends on M1. Blocks every behavior-changing milestone after it.*
*Addresses F10; preserves F22's existing seam.*

- A conventional pytest baseline, with isolated temporary data directories.
- Injectable DMX transport and injectable LedFx client, each with a null
  implementation. The ILDA `PointSink`/`NullSink` design is retained as-is —
  it is already correct.
- An opt-in no-hardware composition that cannot reach real sACN, LedFx, or
  laser output.
- Import-safety and lifecycle regression coverage protecting M1.
- Characterization tests written *before* any legacy behavior is changed.

## M3 — Atomic storage and explicit errors

*Depends on M2 (characterization tests must exist first).*
*Addresses F7, F8.*

- Atomic writes: temporary file, flush, then `os.replace`.
- Typed read outcomes that distinguish missing, empty, invalid, and corrupt.
- Explicit corruption handling instead of collapse to `[]` / `None`.
- A backup or recovery strategy where justified.
- Windows file-lock behavior considered explicitly, and validated on Windows
  (see [platform_support.md](platform_support.md)).

## M4 — Remove read-time fixture mutation

*Depends on M3 (needs typed outcomes to tell "empty" from "corrupt").*
*Addresses F9.*

- Generic device reads become non-mutating.
- Installation provisioning becomes an explicit, deliberate operation.
- Migration of existing installations is explicit and preserves current data.

This milestone is separated from M3 because it is the finding most likely to
destroy real user data, and it needs M3's error typing to be fixed correctly
rather than papered over.

## M5 — Runtime-state separation and DMX pacing

*Depends on M2.*
*Addresses F4, F5, F6.*

- In-memory desired DMX state, owned by a runtime component.
- Disk removed from the high-frequency control path entirely.
- Monotonic pacing with a configurable refresh rate (DESIGN INTENT targets
  roughly 20 ms / 50 Hz).
- Event- or condition-based updates rather than polling.
- Status and diagnostics surfaced from runtime state.

## M6 — Scene concurrency and explicit preset identity

*Depends on M5.*
*Addresses F14, F15.*

- Active scene state synchronized or versioned by scene generation, so that
  work belonging to a superseded scene cannot apply after a newer selection.
- Positional preset association replaced with explicit device-to-preset
  mappings.
- Deterministic beat advancement.

## M7 — LedFx configuration and integration boundaries

*Depends on M2 (needs an injectable client to test against).*
*Addresses F16, F17.*

- Independent LedFx host and port settings, decoupled from the FastAPI bind
  host.
- Explicit timeouts on every request.
- Defined failure semantics — a LedFx outage must not degrade DMX output.
- A clear worker or async boundary.
- Documented support for: Windows Lights + Windows LedFx; WSL2 Lights +
  Windows LedFx; and LAN-hosted LedFx.

## M8 — Validation and preflight

*Depends on M3.*
*Addresses F11, F18.*

- DMX channel range validation (0–255) and expected channel-length checks.
- Fixture, address, and universe validation.
- Scene and preset reference validation — a scene referencing a missing preset
  is rejected, not silently skipped.
- ILDA library root containment, extension checks, and maximum file size.
- A startup preflight that runs before any physical output is enabled.

## M9 — Security and deployment policy

*Depends on M8.*
*Addresses F12, F13.*

- Safe bind defaults.
- Constrained CORS.
- Authentication, or an explicitly documented operator-access policy.
- A stated distinction between localhost development and trusted-LAN
  deployment.
- Authorization boundaries specifically around hardware output.

## M10 — Fixture profiles and broader rig support

*Depends on M8.*
*Addresses F19.*

Replace hardcoded `gigbar`, `keobin`, and `haze` behavior with profile data:
manufacturer, model, operating mode, channel count, channel definitions,
channel ranges, named values, UI controls, manual versus scene-based behavior,
universe, start address, and profile version. Includes profile validation and
migration away from the hardcoded branches in backend and frontend.

## M11 — Safe physical ILDA output

*Depends on M8 and M9. Requires native-Windows hardware validation.*
*Addresses F18, F22.*

**Do not attach a real laser DAC until all of the following exist:**

- a validated ILDA library root and file validation;
- a DAC adapter boundary behind `PointSink`;
- buffered output;
- a watchdog;
- interlock state;
- an emergency stop;
- safe shutdown;
- output disabled by default;
- native-Windows hardware testing.

Software controls alone do not make laser operation safe. This documentation
must never imply otherwise.

## M12 — Rules-first intelligent scene selection

*Depends on M6.*

Progression, in order: deterministic rules; then a weighted scoring or
recommendation layer; then a contextual bandit **only if evidence justifies
it**; then optionally an external advisor.

**The deleted `stable-baselines3` / `gymnasium` reinforcement-learning
architecture is not to be restored by default.** DEFERRED, with the reason on
record: it carried a large dependency footprint and a transitive PyTorch burden
with no working application path (F24), and no evidence has been presented that
the problem requires reinforcement learning.

The existing plan file `.cursor/plans/ai_scene_selection_1e737ce4.plan.md`
already describes a rules-first layered approach consistent with this
milestone. It is PROPOSED, predates this baseline, and is superseded by this
document where the two differ.

---

## Dependency graph

```
M0 documentation
 │
 ▼
M1 safe import ──────────────────────────────────┐
 │                                               │
 ▼                                               │
M2 tests + output seams ─────────┬───────────┐   │
 │                               │           │   │
 ▼                               ▼           ▼   │
M3 atomic storage           M5 runtime    M7 LedFx
 │         │                   state         config
 ▼         ▼                    │
M4 no      M8 validation ───┐   ▼
 read-time  + preflight     │  M6 scene concurrency
 mutation      │            │   + preset identity
               ▼            ▼            │
          M9 security   M10 fixture      ▼
               │          profiles   M12 rules-first
               ▼                      scene selection
          M11 safe physical ILDA
          (also requires M9)
```
