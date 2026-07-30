# Session Handoff

- **Project:** LightsApp Architecture
- **Repository root:** `/home/griffin/projects/lightsapp-architecture-`
- **Required Python:** 3.12.1
- **Expected interpreter:** `.venv/bin/python`

## Purpose and boundaries

This repository is the LightsApp architecture fork. It supports incremental
architecture research around a FastAPI lighting-control application with
DMX/sACN, LedFx, ILDA, scenes, presets, devices, and runtime state. It is
separate from CursorPipeline.

Agents must work only in this repository unless explicitly instructed
otherwise. They must not inspect or modify CursorPipeline, Obsidian, or any
sibling repository.

Current architecture goals include stronger storage validation, explicit error
handling, a `ShowCatalog` or equivalent authoritative catalog, a runtime
manager, service boundaries, hardware adapters, preflight validation, atomic
persistence, testing, and developer tooling. These are intended directions;
they are not a claim that every component exists.

## Safety rules

Treat hardware as unavailable. Do not run or import `backend/main.py` for
validation, start Uvicorn, transmit DMX/sACN, contact LedFx, or start ILDA or
laser output. Prefer fake, simulated, null, or dependency-injected adapters.

Always set an isolated data path before development or testing:

```bash
export LIGHTSAPP_DATA_DIR="$PWD/.local-data"
```

Do not use automated agents against real show data, and do not modify the
default Linux user data at `~/.local/share/LightsApp/data`.

## Current safe validation

From the repository root with the virtual environment active:

```bash
bash -n scripts/context.sh
./scripts/context.sh
git diff --check
python -c "import fastapi, uvicorn, pydantic, requests, sacn; print('Core imports passed')"
```

The repository also contains a hardware-free ILDA reader smoke check:

```bash
cd backend
../.venv/bin/python -m ilda.test_reader
cd ..
```

None of these commands imports `backend/main.py`.

## Verified limitations

- There is no mature test suite or pytest configuration. The only current
  test-like module is `backend/ilda/test_reader.py`, a standalone ILDA reader
  smoke check.
- Runtime startup is coupled to hardware/network behavior.
  `backend/main.py` initializes application data and creates an sACN sender at
  import time, starts the DMX loop in the FastAPI lifespan, checks LedFx in a
  status loop, and calls `uvicorn.run` at module scope.
- Dependencies are loosely pinned. Most entries in `requirements.txt` have no
  version constraint; only the optional AI-related packages specify minimum
  versions.
- Storage reads use Pydantic validation, but persistence in
  `backend/models/storage.py` writes JSON files directly and is not atomic.
