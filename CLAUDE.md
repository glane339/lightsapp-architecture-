# LightsApp Architecture Instructions

## Project identity and repository boundary

This repository is the **LightsApp architecture fork**, a FastAPI-based
lighting-control application involving DMX/sACN, LedFx, ILDA, scenes, presets,
devices, and runtime state. It is intended for architecture research and
incremental, behavior-conscious improvement.

LightsApp is separate from CursorPipeline. Work only inside:

`/home/griffin/projects/lightsapp-architecture-`

unless the user explicitly instructs otherwise. Do not inspect or modify
CursorPipeline, Obsidian, or any sibling repository.

## Python and development data

- Required Python: **3.12.1**
- Expected interpreter: `.venv/bin/python`
- Set `LIGHTSAPP_DATA_DIR` to an isolated development directory such as
  `$PWD/.local-data`.
- Never read, write, migrate, or test against real user application data at
  `~/.local/share/LightsApp/data`.
- Never commit generated runtime data, credentials, local network
  configuration, logs, or machine-specific files.
- AI dependencies and AI-mode code are optional unless the task explicitly
  concerns them.

## Change discipline

Make architecture changes incrementally and preserve behavior where practical.
Prefer characterization tests before changing existing behavior. Avoid
unrelated refactors or broad production rewrites. Do not silently change
storage formats, persistence semantics, output behavior, or runtime behavior.
Keep failures explicit and changes reviewable.

## Hardware and runtime safety

Assume hardware is unavailable unless the user explicitly says otherwise. Do
not start DMX, sACN, LedFx, ILDA, laser, or any other hardware/network output
for inspection or validation. Do not import or run `backend/main.py` during
ordinary validation: it currently initializes runtime data, constructs and
starts an sACN sender, and invokes Uvicorn at module scope.

Prefer fake, simulated, null, or dependency-injected hardware adapters. Run
only hardware-safe validation before claiming completion, such as syntax
checks, pure-unit tests, the ILDA reader smoke check, and dependency imports
that do not import `backend/main.py`.

## Architecture direction

These are targets for the architecture fork, not assertions that every
component already exists:

- storage validation at system boundaries;
- explicit error handling;
- a `ShowCatalog`, or equivalent authoritative catalog;
- a runtime manager for live state and orchestration;
- service boundaries around API, storage/catalog, runtime, and integrations;
- hardware adapters for DMX/sACN, LedFx, ILDA, and future outputs;
- preflight validation before applying shows or enabling output;
- atomic persistence;
- hardware-safe characterization, unit, and integration testing;
- repeatable developer tooling.

Inspect the current code before claiming any target is implemented.
