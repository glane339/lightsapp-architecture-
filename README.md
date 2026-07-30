# LightsApp Architecture

LightsApp Architecture is the architecture fork of a FastAPI lighting-control
application covering DMX/sACN, LedFx, ILDA, scenes, presets, devices, and
runtime state. It is separate from CursorPipeline and is intended for
architecture research and incremental, behavior-preserving improvement.

Work in this repository only. Do not inspect or modify sibling repositories.
See `AGENTS.md` and `CLAUDE.md` for the complete contributor and hardware-safety
boundaries.

## Environment

LightsApp requires Python **3.12.1**. From WSL2:

```bash
cd ~/projects/lightsapp-architecture-
uv python install 3.12.1
uv venv --python 3.12.1 .venv
source .venv/bin/activate
uv pip install --python .venv/bin/python -r requirements.txt
```

`uv venv` environments may initially lack `pip`. The `uv pip install
--python ...` command above installs requirements directly into the selected
environment and does not require `python -m pip`.

The expected interpreter is:

`/home/griffin/projects/lightsapp-architecture-/.venv/bin/python`

## Cursor

Open only this repository:

```bash
cd ~/projects/lightsapp-architecture-
cursor .
```

In Cursor, select the Python interpreter:

`/home/griffin/projects/lightsapp-architecture-/.venv/bin/python`

## Safe CLI startup

Set an isolated data directory before starting an agent. These commands do not
launch LightsApp:

```bash
cd ~/projects/lightsapp-architecture-
source .venv/bin/activate
export LIGHTSAPP_DATA_DIR="$PWD/.local-data"
./scripts/context.sh
codex
```

```bash
cd ~/projects/lightsapp-architecture-
source .venv/bin/activate
export LIGHTSAPP_DATA_DIR="$PWD/.local-data"
./scripts/context.sh
claude
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

The existing ILDA reader smoke check is also hardware-safe. It must run with
`backend` on the Python import path:

```bash
cd backend
../.venv/bin/python -m ilda.test_reader
cd ..
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

## Optional user-local aliases

The following examples belong in the user's local shell configuration (for
example `~/.bashrc`). They must not be committed to this repository:

```bash
alias codex-lightsapp='cd ~/projects/lightsapp-architecture- && source .venv/bin/activate && export LIGHTSAPP_DATA_DIR="$PWD/.local-data" && ./scripts/context.sh && codex'
alias claude-lightsapp='cd ~/projects/lightsapp-architecture- && source .venv/bin/activate && export LIGHTSAPP_DATA_DIR="$PWD/.local-data" && ./scripts/context.sh && claude'
```
