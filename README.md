# LightsApp Architecture

LightsApp Architecture is the architecture fork of a FastAPI lighting-control
application covering DMX/sACN, LedFx, ILDA, scenes, presets, devices, and
runtime state. It is separate from CursorPipeline and is intended for
architecture research and incremental, behavior-preserving improvement.

Work in this repository only. Do not inspect or modify sibling repositories.
See `AGENTS.md` and `CLAUDE.md` for the complete contributor and hardware-safety
boundaries.

## Documentation

The canonical documentation lives in [docs/](docs/). If you are new to this
repository, read the first four in order.

| Document | What it answers |
| --- | --- |
| [docs/project_overview.md](docs/project_overview.md) | What Lights is, what it does, the state of every feature, and the evidence labels used throughout |
| [docs/architecture.md](docs/architecture.md) | How it works today, the creator's design intent, and the target architecture — kept strictly separate |
| [docs/audit_findings.md](docs/audit_findings.md) | Verified defects F1–F25, prioritized, with the statements that must not be repeated about them |
| [docs/current_sprint.md](docs/current_sprint.md) | The milestone in progress and the next branch's exact scope |
| [docs/roadmap.md](docs/roadmap.md) | Dependency-ordered milestones M0–M12 |
| [docs/platform_support.md](docs/platform_support.md) | WSL2 development versus native-Windows hardware validation |
| [docs/decisions.md](docs/decisions.md) | Accepted decisions (D-1…) and open questions needing an owner (OQ-1…) |
| [docs/session_handoff.md](docs/session_handoff.md) | Operational state for the next session |

A second set describes where Lights is proposed to go: a synchronized
show-control system driving WLED and DMX fixtures from analyzed audio files.
**None of it is implemented**, and every document says so in its own banner.

| Document | What it answers |
| --- | --- |
| [docs/show_control_architecture.md](docs/show_control_architecture.md) | The layered show-control architecture, and a capability-by-capability current-versus-future table |
| [docs/audio_reactivity_architecture.md](docs/audio_reactivity_architecture.md) | Why complete-file analysis beats microphone-only, and how the audio pipeline would work |
| [docs/fixture_and_transport_strategy.md](docs/fixture_and_transport_strategy.md) | Fixture profiles as data, capability-based rendering, and the WLED/DMX transports |
| [docs/laser_and_haze_safety.md](docs/laser_and_haze_safety.md) | Safety policy for laser and haze output — **read before any laser or haze work** |
| [docs/show_control_recommendations.md](docs/show_control_recommendations.md) | Every recommended library and tool, with rationale, prerequisites, licensing risk, and impact |
| [docs/show_control_roadmap.md](docs/show_control_roadmap.md) | Phases 1–5, and how they depend on the M0–M12 milestones |

Two conventions carry across all of these. Every substantive claim is labeled
with how much confidence it has earned — VERIFIED CURRENT BEHAVIOR, DESIGN
INTENT, TARGET ARCHITECTURE, and the rest are defined in
[docs/project_overview.md](docs/project_overview.md). And nothing in this
repository is currently HARDWARE VERIFIED.

Superseded documents are marked with a status banner rather than deleted:
`RUN.md`, `QUICK_START.md`, `BUILD_INSTRUCTIONS.md`, and `file_structure.txt`.

## Environment

LightsApp requires Python **3.12.1**. WSL2 is the primary development
environment; native Windows is the deployment and hardware-validation
environment (see [docs/platform_support.md](docs/platform_support.md)). All
commands below are run from the repository root and use repository-relative
paths.

WSL2 / Linux:

```bash
uv python install 3.12.1
uv venv --python 3.12.1 .venv
source .venv/bin/activate
uv pip install --python .venv/bin/python -r requirements.txt
```

Native Windows (PowerShell):

```powershell
uv python install 3.12.1
uv venv --python 3.12.1 .venv
.\.venv\Scripts\Activate.ps1
uv pip install --python .\.venv\Scripts\python.exe -r requirements.txt
```

`uv venv` environments may initially lack `pip`. The `uv pip install
--python ...` command above installs requirements directly into the selected
environment and does not require `python -m pip`.

The expected interpreter is `.venv/bin/python` on WSL2/Linux and
`.venv\Scripts\python.exe` on native Windows, in both cases relative to the
repository root.

## Cursor

Open only this repository:

```bash
cd ~/projects/lightsapp-architecture-
cursor .
```

In Cursor, select the repository's own interpreter: `.venv/bin/python` under the
repository root (`.venv\Scripts\python.exe` on native Windows).

## Safe CLI startup

Set an isolated data directory before starting an agent. These commands do not
launch LightsApp. Run them from the repository root.

WSL2 / Linux:

```bash
source .venv/bin/activate
export LIGHTSAPP_DATA_DIR="$PWD/.local-data"
./scripts/context.sh
codex   # or: claude
```

Native Windows (PowerShell) — `scripts/context.sh` is a Bash script and has no
PowerShell equivalent yet, so skip it there:

```powershell
.\.venv\Scripts\Activate.ps1
$env:LIGHTSAPP_DATA_DIR = Join-Path $PWD ".local-data"
codex   # or: claude
```

`.env.example` contains a placeholder for tools that load `.env` files.
LightsApp itself does not automatically load that file, so exporting the
variable in the shell is the reliable WSL2 setup.

## Hardware-safe validation

Run validation from the repository root with the repository virtual
environment active. This dependency check imports installed packages only; it
does not import `backend/main.py`:

```bash
python -c "import fastapi, uvicorn, pydantic, requests, sacn; print('Core imports passed')"
```

The existing ILDA reader smoke check is also hardware-safe. Run it as a package
module from the repository root — importing `backend` puts `backend/` on
`sys.path` (`backend/__init__.py:1-7`), which is what makes its top-level
`from ilda.reader import ...` resolve:

```bash
.venv/bin/python -m backend.ilda.test_reader
```

```powershell
.\.venv\Scripts\python.exe -m backend.ilda.test_reader
```

Do not run or import `backend/main.py` as ordinary validation. It currently
initializes application data, constructs and starts an sACN sender, starts the
DMX send loop during application lifespan, polls LedFx from its status loop,
and invokes Uvicorn at module scope.

Assume DMX/sACN, LedFx, ILDA/laser, and all other hardware or network outputs
are unavailable unless a task explicitly provides a safe test environment.
Prefer fakes, null sinks, simulation, and dependency injection.

## Application data

On Linux, the default application data directory is:

`~/.local/share/LightsApp/data`

`LIGHTSAPP_DATA_DIR` overrides that default. Development and automated checks
should use a disposable, repository-local path:

```bash
export LIGHTSAPP_DATA_DIR="$PWD/.local-data"
```

The path is ignored by Git. Some backend modules create directories or seed
JSON when imported, so set the override before working with application code.
Never use real show data for automated agent testing, and never modify or
migrate the real user data directory as part of development validation.

The JSON under `backend/data/` is intentionally tracked seed configuration; it
is not the location for generated development state.

## Architecture direction

This fork is moving incrementally toward stronger storage validation, explicit
error handling, a `ShowCatalog` or equivalent authoritative catalog, a runtime
manager, clear service boundaries, hardware adapters, preflight validation,
atomic persistence, and broader hardware-safe testing and developer tooling.
These are direction statements, not claims that all components exist today.
**The target architecture as a complete composition is not implemented** — no
composition root, catalog, runtime manager, preflight service, or atomic
persistence layer exists. A few precursor seams do exist and are worth knowing
about: Pydantic validation on read, the ILDA `PointSink`/`NullSink` output
seam, the `LIGHTSAPP_DATA_DIR` data-directory seam, and the existing developer
tooling under `scripts/`. See [docs/architecture.md](docs/architecture.md)
Part 3 for what exists versus what is proposed, and
[docs/roadmap.md](docs/roadmap.md) for the order in which the rest is being
approached.

## Optional user-local aliases

The following examples belong in the user's local shell configuration (for
example `~/.bashrc`). They must not be committed to this repository:

```bash
alias codex-lightsapp='cd ~/projects/lightsapp-architecture- && source .venv/bin/activate && export LIGHTSAPP_DATA_DIR="$PWD/.local-data" && ./scripts/context.sh && codex'
alias claude-lightsapp='cd ~/projects/lightsapp-architecture- && source .venv/bin/activate && export LIGHTSAPP_DATA_DIR="$PWD/.local-data" && ./scripts/context.sh && claude'
```
