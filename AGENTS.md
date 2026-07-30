# LightsApp Architecture Agent Instructions

## Project identity and boundaries

This repository is the **LightsApp architecture fork**. It is a FastAPI-based
lighting-control application involving DMX/sACN, LedFx, ILDA, scenes, presets,
devices, and runtime state.

LightsApp is separate from CursorPipeline. Work only inside this repository
unless the user explicitly instructs otherwise:

`/home/griffin/projects/lightsapp-architecture-`

Do not inspect or modify CursorPipeline, Obsidian, or any other sibling
repository.

## Environment

- Required Python: **3.12.1**
- Expected interpreter: `.venv/bin/python`
- Use an isolated `LIGHTSAPP_DATA_DIR` for development and testing, normally
  `$PWD/.local-data` from the repository root.
- Never modify real user application data under
  `~/.local/share/LightsApp/data`.
- Do not commit `.local-data/`, generated runtime data, credentials, local
  network configuration, logs, or other machine-specific files.
- AI dependencies and AI-mode code are optional unless the current task
  explicitly concerns them.

## Development approach

- Make architecture changes incrementally and preserve behavior where
  practical.
- Prefer characterization tests before changing existing behavior.
- Avoid unrelated refactors and broad production rewrites.
- Do not silently rewrite storage formats or runtime behavior.
- Keep errors explicit and changes reviewable.

## Hardware and runtime safety

Treat all hardware as unavailable unless the user explicitly states otherwise.
Do not start real DMX, sACN, LedFx, ILDA, laser, or other hardware/network
output merely to inspect or validate code. Do not import or run
`backend/main.py` as a validation step: it currently performs runtime
initialization, constructs and starts an sACN sender, and runs Uvicorn.

Prefer fake, simulated, null, or dependency-injected hardware adapters. Before
claiming completion, run only hardware-safe validation commands. Safe examples
include syntax checks, focused pure-unit tests, the ILDA reader smoke check,
and dependency imports that do not import `backend/main.py`.

## Architecture direction

The following items describe the intended direction, not a claim that each
component already exists:

- validate storage at system boundaries;
- use explicit error handling instead of silent recovery where correctness
  matters;
- establish a `ShowCatalog`, or equivalent authoritative catalog, for show
  definitions;
- separate live state and orchestration into a runtime manager;
- define service boundaries between API routes, catalog/storage, runtime
  orchestration, and integrations;
- place DMX/sACN, LedFx, ILDA, and future outputs behind hardware adapters;
- perform preflight validation before applying a show or activating output;
- use atomic persistence for durable changes;
- expand characterization, unit, and integration testing with hardware-safe
  fakes;
- improve repeatable developer tooling and validation.

Confirm the current implementation before describing any of these targets as
complete.
