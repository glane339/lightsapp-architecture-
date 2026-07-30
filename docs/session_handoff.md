# Session Handoff

**Status of this document:** canonical. Operational state for whoever picks
this up next. Updated during the M0 documentation baseline pass.

- **Project:** LightsApp Architecture
- **Repository root:** `/home/griffin/projects/lightsapp-architecture-`
- **Required Python:** 3.12.1
- **Expected interpreter:** `.venv/bin/python`
- **Branch at last handoff:** `docs/repository-baseline`
- **HEAD at last handoff:** `01e6ba8` (unchanged by this pass — documentation
  is uncommitted in the working tree)

## Where things stand

Milestone M0 (documentation and repository truth) is complete pending an
independent audit. The canonical documentation set now exists under `docs/`.
No production code, frontend code, or dependency was touched.

The next unit of work is M1, on a new branch
`architecture/safe-import-boundary`, scoped and specified in
[current_sprint.md](current_sprint.md).

**Start here:** [project_overview.md](project_overview.md) →
[architecture.md](architecture.md) → [audit_findings.md](audit_findings.md) →
[current_sprint.md](current_sprint.md).

A separate, entirely PROPOSED document set describes where Lights is intended to
go — a synchronized show-control system driving WLED and DMX fixtures from
analyzed audio files. Start at
[show_control_architecture.md](show_control_architecture.md). None of it is
implemented, none of it changes M1's scope, and its proposed decisions are
recorded as `PD-n` in [decisions.md](decisions.md) — which bind nothing until an
owner accepts them.

## Purpose and boundaries

This repository is the LightsApp architecture fork: incremental architecture
research around a FastAPI lighting-control application with DMX/sACN, LedFx,
ILDA, scenes, presets, devices, and runtime state. It is separate from
CursorPipeline.

Agents must work only in this repository unless explicitly instructed
otherwise. They must not inspect or modify CursorPipeline, Obsidian, or any
sibling repository.

Architecture goals — stronger storage validation, explicit error handling, a
`ShowCatalog` or equivalent authoritative catalog, a runtime manager, service
boundaries, hardware adapters, preflight validation, atomic persistence,
testing, and developer tooling — are intended directions. **The target
architecture as a complete composition is not implemented**, though a few
precursor seams do exist. [architecture.md](architecture.md) Part 3 states
which is which.

## Safety rules

Treat hardware as unavailable. Do not run or import `backend/main.py` for
validation, start Uvicorn, transmit DMX/sACN, contact LedFx, or start ILDA or
laser output. Prefer fake, simulated, null, or dependency-injected adapters.

Always set an isolated data path before development or testing
(`LIGHTSAPP_DATA_DIR`; the exact command per platform is in
[platform_support.md](platform_support.md)). Do not run automated agents
against real show data, and do not modify the default Linux user data at
`~/.local/share/LightsApp/data`.

The prohibition on importing `backend/main.py` is not caution for its own sake.
Importing it creates the data directory through a transitive import, seeds JSON
files, constructs and starts an sACN sender, and calls `uvicorn.run` — all at
module scope. See findings F1–F3 in [audit_findings.md](audit_findings.md).
This restriction lifts only when M1 is complete and verified.

## Current safe validation

The canonical command list, for both WSL2 and native Windows PowerShell, is in
[platform_support.md](platform_support.md) under "Current hardware-safe
validation commands". It is not duplicated here — that list is the single
source of truth, and a copy in this file would drift.

Nothing on that list imports `backend/main.py`, and launching the packaged
executable is deliberately not on it.

## Known limitations

The verified findings, with file and line evidence, are in
[audit_findings.md](audit_findings.md) as F1–F25. That document is the single
source of truth for them; this file does not restate them.

The short orientation, by finding number: startup executes the application
(F1–F3), the DMX loop is unpaced and disk-bound (F4–F6), writes are not atomic
and read errors are ambiguous (F7, F8), reading devices can write to storage
(F9), there is no test suite (F10), there is no authentication and CORS is
wildcarded (F12, F13), fixture support is rig-specific (F19), dependencies are
unpinned (F21), and ILDA output is nonphysical (F22).

## Open questions awaiting an owner

Eight are recorded in [decisions.md](decisions.md). None blocks M1. The ones
worth raising with the owner soonest:

- **OQ-5** — which real installations must survive the M4 migration.
- **OQ-3** — the deployment threat model, needed before M9.
- **OQ-1** — confirm the milestone numbering range. Nonblocking; work proceeds
  under M0–M12 until told otherwise.

## For the next session

1. Read the four documents listed under "Where things stand".
2. Confirm HEAD is still `01e6ba8`; if it has moved, re-verify the findings in
   [audit_findings.md](audit_findings.md) before relying on them.
3. If the M0 documentation audit is complete, create
   `architecture/safe-import-boundary` and work the acceptance criteria in
   [current_sprint.md](current_sprint.md).
4. Do not widen the M1 branch beyond its stated scope.
