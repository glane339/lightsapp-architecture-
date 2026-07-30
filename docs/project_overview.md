# Project Overview

**Status of this document:** canonical. Established on branch
`docs/repository-baseline` against HEAD `01e6ba8`.

This document answers: what is Lights, what does it currently do, and what is
the state of each feature. For *how* it works internally see
[architecture.md](architecture.md). For known defects see
[audit_findings.md](audit_findings.md).

## Evidence labels used across this documentation set

Every substantive claim in these documents carries one of these labels, either
inline or by section heading. They are not decoration: they record how much
confidence a statement has earned.

| Label | Meaning |
| --- | --- |
| VERIFIED CURRENT BEHAVIOR | Confirmed against repository code at HEAD `01e6ba8` by the Codex read-only audit and re-checked during this pass. |
| CODE-INSPECTED ONLY | Read from source and believed accurate, but not exercised at runtime and not independently audited. |
| HARDWARE VERIFIED | Confirmed against physical fixtures or real integrations on native Windows. **Nothing in this repository currently carries this label.** |
| DESIGN INTENT | From the creator's block diagram or Lighting Models spreadsheet. Describes what the system is meant to become, not what exists. |
| TARGET ARCHITECTURE | A structural end-state this fork is working toward. Not implemented. |
| PROPOSED | A specific suggestion that has not been accepted as a decision. |
| DEFERRED | Deliberately postponed, with a reason recorded. |
| UNKNOWN | Not established either way. Requires investigation or an owner decision. |

Two rules govern their use. Completion percentages are never used, because
nothing in the current evidence base supports them. And no component is
described as implemented without repository evidence.

## What Lights is

Lights is a single-operator lighting controller for one specific lighting rig.
It is a FastAPI backend serving a vanilla-JavaScript frontend, persisting all
state as JSON files, and driving three output paths: DMX over sACN/E1.31,
LedFx scene activation over HTTP (with WLED behind the external LedFx process),
and ILDA laser-frame parsing and sequencing.

It is a compact and coherent prototype rather than a general-purpose lighting
platform. The domain model is recognizable and the workflow is consistent —
this is an application with a design, not a collection of scripts. The
architecture fork's purpose is to stabilize it incrementally. A rewrite is
explicitly not the plan.

**Scope is currently rig-specific.** VERIFIED CURRENT BEHAVIOR: fixture
knowledge for `gigbar`, `keobin`, and `haze` is hardcoded in both backend and
frontend, including channel counts, classification behavior, and special
controls. Adding a fixture currently requires code changes. Lights does not
have generalized fixture support.

## The domain model

VERIFIED CURRENT BEHAVIOR. The persisted object graph, read from the Pydantic
models in `backend/models/`:

```
DMXDevice          id, order, channels, active_channels[], control_type
DEVICEPreset       id, device, channel_values[]
Preset             id, device_presets[] (ids), ledfx_setting (string)
Scene              id, preset_ids[]
IldaFrame          id, path
IldaScene          id, ilda_frames[], beat_synced, time_step,
                   points_per_second, animation_speed, dwell_seconds
FullScene          id, scene_id, ilda_scene_id
CONFIG             id, total_channels, IP, sacn_port, priority, universe,
                   server_host, server_port, ai_mode_enabled
```

The composition chain runs:

```
device preset  →  combined preset  →  scene  →  full scene  →  active show
(per-device       (several device      (list of   (scene +      (beat-driven
 channel values)   presets + one       presets)    ILDA scene)   advancement)
                   LedFx scene name)
```

Each layer names the layer below it by string ID. There are no foreign-key
constraints and no referential-integrity checks; a scene may reference a preset
that no longer exists, and this is not detected until application time.

## Current feature state

| Feature | State | Label |
| --- | --- | --- |
| Device (fixture) definition and manual channel control | Implemented for the hardcoded rig | VERIFIED CURRENT BEHAVIOR |
| Device presets — named channel values per fixture | Implemented | VERIFIED CURRENT BEHAVIOR |
| Combined presets — several device presets plus a LedFx scene name | Implemented; device association is positional | VERIFIED CURRENT BEHAVIOR |
| Scenes — ordered lists of combined presets | Implemented | VERIFIED CURRENT BEHAVIOR |
| Full scenes — a scene plus an optional ILDA scene | Implemented | VERIFIED CURRENT BEHAVIOR |
| Active show control — apply a full scene, advance on beat | Implemented; state is unsynchronized | VERIFIED CURRENT BEHAVIOR |
| Browser microphone beat detection | Implemented in frontend JS | CODE-INSPECTED ONLY |
| DMX output over sACN/E1.31 | Implemented; send loop is unpaced | VERIFIED CURRENT BEHAVIOR |
| DMX output against physical fixtures | No evidence in repository | UNKNOWN / not HARDWARE VERIFIED |
| LedFx scene activation | Implemented; synchronous, host/port coupling defect | VERIFIED CURRENT BEHAVIOR |
| ILDA `.ild` file parsing | Implemented, with a smoke check | VERIFIED CURRENT BEHAVIOR |
| ILDA scene sequencing (beat or timed) | Implemented | VERIFIED CURRENT BEHAVIOR |
| ILDA output to a physical laser DAC | **Does not exist.** Playback drives a `LoggingSink` that counts points | VERIFIED CURRENT BEHAVIOR |
| AI mode | Broken. Routes import the deleted `backend/ai_mode` package and are omitted at startup | VERIFIED CURRENT BEHAVIOR |
| Windows executable build (PyInstaller) | Scripts and spec exist in repository | CODE-INSPECTED ONLY |
| Automated test suite | Does not exist. One CLI smoke script only | VERIFIED CURRENT BEHAVIOR |
| Authentication or authorization | Does not exist on any route | VERIFIED CURRENT BEHAVIOR |

**What "implemented" means in this table.** The workflow and the output paths
are present and coherent in code — that is the extent of the evidence. It is
*not* a claim that fixtures respond, that the browser microphone works in a
host browser, or that the application has been used in a real show. Those are
unverified and appear as unchecked rows on the native-Windows checklist in
[platform_support.md](platform_support.md).

### On the two features most likely to be misread

**ILDA output is nonphysical.** `IldaPlayer` streams parsed points into
`LoggingSink`, which increments counters and prints a total. There is no DAC
driver, no USB or Ethernet laser transport, and no interlock. This is a
functional limitation, and it is currently also a safety property: the
application cannot presently emit laser output. Do not describe Lights as
having laser output.

**AI mode is orphaned, not removed.** `backend/routes/ai_mode.py` imports from
`backend/ai_mode`, a package that git history records as deleted.
`backend/main.py` wraps the router registration in `try/except`, so the app
starts and the `/api/ai-mode/*` endpoints are simply absent. The frontend page
`frontend/html/ai_mode.html` is not linked from any tracked navigation, but the
static mount still serves it, so the page remains directly addressable by URL.
It is unlinked and functionally orphaned — not physically unreachable. The
heavyweight reinforcement-learning dependencies (`stable-baselines3`,
`gymnasium`, `numpy`) remain in `requirements.txt` with no working code path.

## Strengths worth preserving

These come from the earlier Claude architectural audit and survived Codex
review. They are the reasons incremental stabilization is the right strategy.

1. The repository is small enough to hold in your head — a few dozen tracked
   files across a handful of backend packages and a frontend with no build step.
2. There is a real domain model and a coherent workflow.
3. FastAPI plus vanilla JavaScript is appropriately sized for the project.
4. Browser-side microphone analysis is a sound design: raw audio never leaves
   the browser, and the backend receives derived beat events instead of an
   audio stream. The design is readable from the code; whether the capture
   works in a host browser is CODE-INSPECTED ONLY. This is a strength of the
   current implementation, not a commitment that the future system-audio source
   must remain browser-side.
5. Pydantic models already validate data on read.
6. Governance and handoff documentation is unusually strong for a prototype.
7. The ILDA subsystem is the most cohesive part of the codebase: it uses a
   lock, a stop event, a `PointSink` protocol, and both `NullSink` and
   `LoggingSink` implementations.
8. `LIGHTSAPP_DATA_DIR` is a genuinely useful cross-platform data-directory
   seam.
9. Windows launcher and PyInstaller work already exists.
10. Existing architecture documentation correctly labels `ShowCatalog`,
    `RuntimeManager`, adapters, preflight, and atomic persistence as future
    direction rather than claiming they are implemented.

## Where this is going

Incremental modernization, in dependency order, tracked in
[roadmap.md](roadmap.md). The near-term priorities are making the application
importable without side effects, establishing hardware-safe tests, and making
persistence atomic and its failures explicit. Everything else depends on those
three.

The approved show-control direction is live-first. Lights is primarily intended
for parties with unpredictable Spotify playback, where the original audio file
is usually unavailable before a track begins. Real-time system-audio capture is
the planned source of truth, microphone capture is the fallback, Spotify
metadata is an optional identity and transition enhancement, and offline file
analysis remains optional for prepared tracks, cached analysis, testing, and
special events.

The future pipeline normalizes every source into a shared feature vocabulary,
stabilizes live musical-state estimates, emits semantic cues, and renders them
through a retained LedFx compatibility adapter, a growing native WLED renderer,
and a fixture-aware DMX renderer. Lasers and atmosphere remain behind explicit
safety policy. **None of these future components exists today.** The canonical
description and current-versus-future table are in
[show_control_architecture.md](show_control_architecture.md).

## Related documents

- [architecture.md](architecture.md) — how the current system works, and the target shape
- [audit_findings.md](audit_findings.md) — verified defects, prioritized
- [roadmap.md](roadmap.md) — dependency-ordered milestones M0–M12
- [platform_support.md](platform_support.md) — WSL2 development vs native-Windows validation
- [decisions.md](decisions.md) — accepted decisions and open questions
- [current_sprint.md](current_sprint.md) — the milestone in progress
- [session_handoff.md](session_handoff.md) — operational state for the next session
