# Audit Findings

**Status of this document:** canonical. Findings verified by the Codex
read-only audit against HEAD `01e6ba8`, and re-checked against the working tree
during the `docs/repository-baseline` pass. HEAD was unchanged and all
production code, frontend code, and dependency files matched HEAD `01e6ba8`, so
no drift re-verification of the findings was required. Documentation changes
were present in the working tree and uncommitted during that pass.

All findings below are **VERIFIED CURRENT BEHAVIOR** unless a finding says
otherwise. Findings are numbered `F1`–`F25` for stable cross-reference; the
numbers carry no priority meaning beyond the section they sit in.

Priorities describe *sequencing*, not severity of consequence. P0 findings are
startup, data-integrity, and safety concerns that block confident work on
everything else. P1 findings are serious but sit behind P0 in dependency order.

## Provenance and how to read this

Three sources fed this document, in decreasing authority: the repository code
itself, the Codex read-only verification audit, and an earlier Claude
architectural audit. Codex verified specific claims against repository
evidence. The earlier Claude audit supplied architectural interpretation and
context, and Codex corrected several of its statements — those corrections are
recorded in the final section and **must not be re-introduced**.

---

## P0 — Startup, data integrity, and safety

### F1. Importing `backend/main.py` executes the application

`backend/main.py:14,29-32,156`, `backend/dmx/sender.py:9`,
`backend/routes/data.py:16-17`

Importing the entry module performs the following at module scope, in this
order:

1. `from dmx.sender import SENDER` (`backend/main.py:14`) transitively imports
   `routes.data` (`backend/dmx/sender.py:9`), whose module scope calls
   `_DATA_DIR.mkdir(parents=True, exist_ok=True)` (`backend/routes/data.py:16-17`).
   **The data directory is therefore created by an import side effect, before
   any seeding logic has run.**
2. `ensure_data_initialized(...)` (`backend/main.py:29`) then seeds the
   directory: it copies seed JSON from `backend/data/` and writes a default
   `config.json` and empty `[]` files for anything missing.
3. Two lines are printed to stdout (`backend/main.py:30-31`).
4. The global `SENDER` is constructed (`backend/main.py:32`), which starts sACN
   — see F3.
5. `uvicorn.run` is called unconditionally (`backend/main.py:156`) — see F2.

Importing `backend/routes/data.py` on its own, or importing anything that
reaches it, is sufficient to trigger step 1 by itself.

*Impact:* ordinary inspection is unsafe, ASGI import tooling is unsafe, imports
may create or copy JSON files, imports activate output infrastructure, and an
import can block in server startup. This finding is the reason every governance
document in this repository forbids importing `main.py` for validation.

### F2. `uvicorn.run` is unconditional

`backend/main.py:156`

Executed at module scope with no `if __name__ == "__main__":` guard.

*Impact:* importing the module launches the server. Standard ASGI tooling
(`uvicorn backend.main:app`, test clients, schema extraction) cannot be used.

### F3. sACN infrastructure starts during import

`backend/main.py:32`, `backend/dmx/sender.py:55-62`

The global `SENDER` is constructed at import. Its `__init__` patches the sacn
library, constructs `sacn.sACNsender`, calls `.start()`, `.activate_output()`,
and configures destination, multicast, and priority.

*Impact:* network output infrastructure is live before FastAPI's lifespan runs.
Inspection or test collection risks activating hardware-related behavior.

### F4. The DMX send loop is unpaced

`backend/main.py:39-59`

`while _dmx_sender_running: sender.send()` with no sleep, condition wait, event
wait, or refresh pacing. The source comment states the sacn library handles
throttling. The only time-based logic in the loop rate-limits *error logging*,
not iterations.

*Impact:* CPU spin, repeated application work, continuous disk parsing.

*Do not misstate this:* the sacn library may throttle packet publication
internally, but that does not pace the application loop, which continues to
perform filesystem reads and Pydantic validation at full speed.

### F5. `devices.json` is re-read on every send iteration

`backend/dmx/sender.py:69-86`

`SENDER.send()` resolves the data path and calls `load_optional` on
`devices.json` on every call. Combined with F4, this happens continuously.

*Impact:* high filesystem activity, repeated JSON parsing, repeated Pydantic
validation, greater exposure to partially written files, and disk behavior
directly affecting output timing.

### F6. JSON persistence is used as the live DMX control bus

`backend/routes/post.py:74`, `backend/dmx/sender.py:74`

API routes persist device changes to `devices.json`; the DMX thread polls that
same file as its source of live output state.

*Impact:* durable storage doubles as inter-thread IPC. Output latency depends
on disk behavior, output correctness depends on write/read timing, and
persistent configuration is coupled to transient runtime state.

*Relationship to F4 and F5 — these are related but independent defects.* File
polling is what makes each iteration re-parse and re-validate `devices.json`
(F5) and what exposes the output path to partially written files (F7). The
unpaced loop (F4) has a separate cause: the loop body contains no
application-level wait. Removing the polling would not by itself pace the loop,
and adding pacing would not by itself remove the disk from the control path.
Both must be fixed, and M5 addresses them together.

### F7. JSON writes are non-atomic

`backend/models/storage.py:34-43`

`save` and `save_single` open the final destination with `"w"` and `json.dump`
directly into it. No temporary file, no flush strategy, no `fsync`, no
`os.replace`, no recovery path.

*Impact:* a concurrent reader — including the DMX thread on every iteration —
may observe truncated or partially written JSON. A crash during a write
destroys the last valid version.

### F8. Storage failures collapse into ambiguous empty results

`backend/models/storage.py:10-31`

Loaders catch `FileNotFoundError`, `json.JSONDecodeError`, and
`ValidationError`, returning `[]` or `None`. Missing files and malformed JSON
are silent; validation failures print first. Other `OSError` subclasses
propagate.

*Impact:* callers cannot distinguish legitimately empty data from missing,
malformed, or schema-invalid data.

*Do not overstate this:* it is **not** true that every storage error is
silently swallowed. State it precisely — missing files and malformed JSON may
be silently converted to empty results, validation failures print and return
empty results, and some other OS errors propagate.

### F9. Generic device reads can mutate persistent storage

`backend/routes/data.py:38-139`

`load_devices()` is a read that may write. If the load returns empty it
reconstructs devices from `device_presets.json` and saves. It then appends a
`haze` device if absent, bootstraps `gigbar` and `keobin` if no scene-based
device exists, and rewrites `control_type` on those two if marked manual —
persisting after each step.

*Impact:* read operations mutate storage; corrupt or empty data may be silently
replaced with installation-specific fixture defaults. This compounds F7 and F8:
a truncated read can be interpreted as "empty" and answered by *overwriting the
file* with rig defaults.

*Mitigation that exists:* `save_devices()` refuses to write an empty list
(`backend/routes/data.py:142-147`).

### F10. No conventional automated test suite exists

The only tracked test-like Python file is `backend/ilda/test_reader.py`, a
command-line ILDA smoke script, not a pytest module. There is no pytest
configuration and no tracked regression suite covering startup, storage, scene
logic, output safety, or hardware boundaries.

*Impact:* architectural changes have no regression protection, and
hardware-output safety is not test-enforced.

### F11. DMX channel values lack range and length validation

`backend/models/device.py`, `backend/models/device_presets.py`

`active_channels` and `channel_values` are plain `list[int]`. Nothing enforces
values in 0–255, expected channel count, expected list length, or
fixture-specific channel structure. A hardware-free model check accepted `-1`
and `256`.

*Impact:* invalid values can be persisted and can reach the sACN assignment
path, where output may fail repeatedly or be rejected downstream.

### F12. Mutation and output routes have no authentication

Repository-wide inspection found no authentication or authorization on any
route — no `Depends` guard, no API key, no bearer scheme.

*Impact:* any client that can reach the server may alter fixtures, scenes,
presets, DMX state, and integration behavior. This becomes serious the moment
the server is bound beyond localhost, which `RUN.md` and `BUILD_INSTRUCTIONS.md`
both instruct operators to do for LAN access.

### F13. CORS is wildcarded

`backend/main.py:119-125`

`allow_origins=["*"]`, `allow_methods=["*"]`, `allow_headers=["*"]`, with
`allow_credentials=True`.

*Impact:* any browser origin may call the API cross-origin. Note that CORS is a
browser-enforced control and is no protection against non-browser clients — it
compounds F12 rather than substituting for a fix.

---

## P1 — Correctness, integration, and maintainability

### F14. Active-scene runtime state is unsynchronized

`backend/routes/active_scene.py:2-8`

Active scene state is a module-global mutable dict, read and modified without
any lock. FastAPI sync handlers execute concurrently in worker threads.

*Impact:* set, clear, and advance operations can interleave. An advancement may
apply a preset belonging to a previous scene after a newer scene has been
selected, and a caller may observe state mixed across scene generations.

### F15. Preset-to-device association is positional

`backend/routes/post.py:52-56`

`chosen_ids[i]` is paired with `scene_based[i]` — the *i*-th entry of
`Preset.device_presets` applies to the *i*-th scene-based device in order.

*Impact:* reordering or omitting entries silently changes or suppresses which
device a preset applies to. Device identity is implicit in list position rather
than stated.

*Do not overstate this:* the subsequent lookup matches on **both** normalized
device ID and normalized preset ID (`backend/routes/post.py:58-61`), so a
mismatch is **skipped, not cross-applied**. Do not claim the code freely
applies one device's preset to another device.

### F16. LedFx calls are synchronous, with inconsistent timeouts

`backend/ledfx/client.py:22,28,45`

`set_active_scene` uses `requests.put(..., timeout=5)`. `get_scenes` and
`get_active_scene` issue `requests.get` with **no timeout**.

*Impact:* worker threads can block, requests can accumulate, and beat-related
work can stall — particularly via the 1 Hz status loop, which performs a
LedFx GET on every tick.

*Do not overstate this:* sync endpoints run in FastAPI's worker pool and the
status path explicitly uses `asyncio.to_thread`. Do not claim LedFx directly
blocks FastAPI's asyncio event loop. The accurate statement is that these calls
may block or accumulate worker requests.

### F17. LedFx configuration is coupled to the FastAPI bind host

`backend/ledfx/client.py:18`

`self.base_url = f"http://{config.server_host}:8888/api"` — the LedFx
destination reuses the server's own bind host and hardcodes port 8888. No
dedicated LedFx host or port setting exists.

*Impact:* setting `server_host` to `0.0.0.0` for LAN access yields
`http://0.0.0.0:8888/api` as the LedFx destination. A remote LedFx cannot be
configured at all, which makes a split WSL2/Windows deployment impossible to
express correctly.

### F18. ILDA file paths are unconfined

`backend/ilda/reader.py:65-67`, `backend/models/ildaframe.py`

`IldaFrame.path` is an arbitrary string; `read_ild_file` performs
`Path(path).read_bytes()`. There is no library root containment, no extension
check, and no maximum file size.

*Impact:* absolute paths, traversal paths, and files outside any configured
root can be read and parsed; large files can exhaust memory. **This must be
resolved before any real DAC output is enabled** — see M8 and M11.

### F19. Fixture behavior is hardcoded

`backend/routes/data.py:57-125`, `frontend/js/presets.js`,
`frontend/js/active.js`, `frontend/js/device_presets.js`

Explicit `gigbar`, `keobin`, and `haze` logic appears in both backend and
frontend: fixture names, channel counts, channel maps, special controls, and
classification behavior.

*Impact:* adding a fixture requires code changes in multiple layers, and
fixture *identity* implicitly triggers behavior. The current implementation is
rig-specific. **Lights does not have generalized fixture support** and must not
be described as if it does.

### F20. AI backend routes import a deleted package

`backend/routes/ai_mode.py:14-16`

The module imports `ai_mode.state`, `ai_mode.feedback`, and
`ai_mode.audio_features` from `backend/ai_mode`, a package absent from the tree
and recorded as deleted in git history. `backend/main.py:138-146` catches the
resulting import failure and omits the router.

*Impact:* `/api/ai-mode/*` is unavailable. The application starts normally.

### F21. Core dependencies are unpinned

`requirements.txt`

`sacn`, `pydantic`, `typing`, `urllib3`, `requests`, `uvicorn`, and `fastapi`
carry no version constraints. Only the AI packages specify minimums. (`typing`
is also listed as a dependency twice, though it is a standard-library module.)

*Impact:* installations can change or break without any repository change,
making environments non-reproducible.

---

## P2 / P3 — Lower priority

### F22. ILDA has an abstraction seam but no physical driver

`backend/ilda/sink.py`, `backend/ilda/player.py:8`

`PointSink` (Protocol), `NullSink`, and `LoggingSink` exist. `IldaPlayer`
currently uses `LoggingSink`, which counts points and prints a total. No DAC or
physical laser driver is present.

*Impact:* Lights can parse and sequence ILDA but cannot drive a physical laser.
This is a functional limitation and, at present, a safety property.

### F23. The AI frontend page is orphaned but addressable

`frontend/html/ai_mode.html`, `backend/main.py:150-151`

No tracked frontend navigation links to the page, and its backend API is absent
(F20). The `StaticFiles` mount at `/` still serves it, so it remains directly
reachable by URL.

*Do not overstate this:* describe it as unlinked and functionally orphaned,
dependent on absent endpoints. Do not describe it as physically unreachable.

### F24. Heavy AI dependencies remain with no working code path

`requirements.txt`

`stable-baselines3>=2.0.0`, `gymnasium>=0.29.0`, and `numpy>=1.24.0` have no
reachable application path. NumPy is imported only by the AI route, which fails
before registration.

*Impact:* large install footprint, a transitive PyTorch burden, and
compatibility risk, with no working feature justifying any of it.

### F25. Existing future-architecture documentation is correctly labeled

`README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/session_handoff.md`

These discuss `ShowCatalog`, `RuntimeManager`, service boundaries, adapters,
preflight, and atomic persistence. Repository inspection did not find these as
production components — but the documentation explicitly presents them as
future direction.

*This is a positive finding.* Do not criticize the existing documentation for
falsely claiming these are implemented. It does not. Preserve the
current-versus-target distinction that is already there.

---

## Corrected critical-issue summary

The most consequential verified problems, in the order they should be
addressed:

1. Importing the entry module initializes data, activates sACN infrastructure,
   and invokes Uvicorn. (F1, F2, F3)
2. The unpaced DMX loop repeatedly re-parses `devices.json`, using persistent
   storage as the live output channel. (F4, F5, F6)
3. Non-atomic writes combine with ambiguous empty fallbacks and read-time
   fixture bootstrapping to create a credible corruption-and-unintended-
   replacement path. (F7, F8, F9)
4. Mutation and output APIs have no authentication, alongside wildcard CORS and
   documented LAN exposure. (F12, F13)
5. DMX values lack application-level range and length validation. (F11)
6. No automated hardware-safe test suite protects runtime changes. (F10)

The following are high priority but belong in P1 rather than as immediate P0
startup and data-safety blockers: the active-scene race (F14), LedFx
configuration and blocking behavior (F16, F17), ILDA path confinement (F18),
positional preset association (F15), hardcoded fixture knowledge (F19), the
broken AI path (F20), and dependency reproducibility (F21).

---

## Statements that must not be repeated

The earlier Claude architectural audit contained overstatements that Codex
corrected against repository evidence. Each pairing below is binding on all
future documentation in this repository.

| Do not say | Say instead |
| --- | --- |
| "LedFx blocks the asyncio event loop." | "LedFx calls are synchronous and may block or accumulate worker requests. Sync endpoints execute in FastAPI's worker pool, and the status path uses `asyncio.to_thread`." |
| "All storage failures are silently swallowed." | "Missing files and malformed JSON may be silently converted to empty results; validation failures print and return empty results; some other OS errors propagate." |
| "Positional mapping can freely apply one device's preset to another." | "Association is position-dependent, but the lookup also checks device identity. Mismatches are skipped rather than cross-applied." |
| "The AI frontend is unreachable." | "The AI page is unlinked and functionally orphaned but remains directly addressable through the static mount." |
| "There are no null adapters." | "ILDA already has `PointSink` and `NullSink` abstractions. DMX and LedFx lack equivalent injectable or null seams." |
| "The current documentation presents future components as implemented." | "Current documentation explicitly presents `ShowCatalog`, `RuntimeManager`, adapters, preflight, and atomic persistence as future direction." |
| "Internal sACN throttling means there is no busy loop." | "The library may throttle packet publication internally, but the application loop remains unpaced and repeatedly performs disk reads and validation." |

One further constraint on provenance: do not state or imply that every item
from the earlier Claude audit was independently verified. Codex verified the
findings recorded in this document. Interpretation and context from the earlier
audit that Codex did not confirm is labeled CODE-INSPECTED ONLY or appears in
[project_overview.md](project_overview.md) as architectural assessment.
