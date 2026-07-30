# Architecture

**Status of this document:** canonical. Established on branch
`docs/repository-baseline` against HEAD `01e6ba8`.

This document describes the architecture as it exists today, the creator's
design intent, and the target architecture this fork is moving toward. These
three are kept strictly separate. Label definitions are in
[project_overview.md](project_overview.md).

---

# Part 1 — Current architecture

## VERIFIED CURRENT BEHAVIOR

Everything in Part 1 was confirmed against repository code at HEAD `01e6ba8`.

## Component map

```
┌─────────────────────────────────────────────────────────────────────┐
│ BROWSER  (vanilla JS, no build step, served from the static mount)  │
│                                                                     │
│  index.html · presets · device_presets · scenes · full_scenes       │
│  ilda · active (Web Audio mic → beat detection)                     │
│  ai_mode.html  ← unlinked, backend endpoints absent                 │
│                                                                     │
│  Hardcoded fixture knowledge: gigbar, keobin, haze                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │ fetch()  →  /api/*
                             │ no authentication · CORS allow_origins=["*"]
┌────────────────────────────▼────────────────────────────────────────┐
│ FastAPI app — backend/main.py  (constructed at MODULE SCOPE)        │
│                                                                     │
│  routers:  get · post · put · delete                                │
│            ai_mode  → ImportError, caught, router omitted           │
│  mount:    StaticFiles("/") serving frontend/, registered last      │
│  lifespan: starts DMX thread + 1 Hz status print loop               │
│  module scope tail: uvicorn.run(app, ...)   ← unguarded             │
└──────┬──────────────────────────────┬───────────────────────────────┘
       │                              │
       │ routes/data.py               │ ledfx/client.py
       │ load_* / save_*              │ requests, synchronous
       │ (creates data dir at import) │ host = config.server_host  ← defect
       │                              │ port = 8888, hardcoded     ← defect
┌──────▼───────────────────────┐  ┌───▼─────────────────────────────┐
│ JSON FILES                   │  │ LedFx HTTP API                  │
│ $LIGHTSAPP_DATA_DIR/         │  │ GET/PUT /api/scenes             │
│   config.json  devices.json  │  │ (external process, WLED behind) │
│   device_presets.json        │  └─────────────────────────────────┘
│   presets.json  scenes.json  │
│   ilda_frames.json           │  ┌─────────────────────────────────┐
│   ilda_scenes.json           │  │ ILDA subsystem                  │
│   full_scenes.json           │  │ reader → playback → IldaPlayer  │
│                              │  │ PointSink protocol              │
│ writes: open("w") + dump     │  │   NullSink   (no output)        │
│         NOT atomic           │  │   LoggingSink (counts points)   │
└──────▲───────────────────────┘  │ NO DAC DRIVER EXISTS            │
       │                          └─────────────────────────────────┘
       │ re-read on EVERY iteration
       │
┌──────┴────────────────────────────────────────────────────────────┐
│ dmx_sender_loop  —  daemon thread, NO sleep / wait / pacing        │
│   while running:  SENDER.send()                                    │
│     → get_data_dir() → load devices.json → Pydantic validate       │
│     → MAPPER → DMXFrame → pad/truncate to 512                      │
│     → sender[universe].dmx_data = tuple(...)                       │
└──────────────────────────┬─────────────────────────────────────────┘
                           │  sacn library (started during IMPORT)
                           ▼
                    E1.31 / sACN over UDP
                           ┊
                           ┊  intended destination: DMX fixtures
                           ┊  NOT HARDWARE VERIFIED — no repository
                           ┊  evidence of physical fixture response
                           ▼
                      (physical rig)
```

## The startup sequence, and why it is a problem

Importing `backend/main.py` is not a passive act. In order, at module scope:

1. **The data directory is created by a transitive import, before any seeding
   runs.** `from dmx.sender import SENDER` (`backend/main.py:14`) imports
   `routes.data` (`backend/dmx/sender.py:9`), whose module scope executes
   `_DATA_DIR.mkdir(parents=True, exist_ok=True)`
   (`backend/routes/data.py:16-17`). Importing anything that reaches
   `routes.data` is enough to trigger this on its own.
2. `ensure_data_initialized(...)` then seeds that directory: it copies seed JSON
   from `backend/data/` and writes a default `config.json` and empty `[]`
   files for anything missing (`backend/main.py:29`, `backend/paths.py:47-72`).
3. Two lines are printed to stdout (`backend/main.py:30-31`).
4. `SENDER(...)` is constructed (`backend/main.py:32`). Its `__init__` patches
   the sacn library, constructs `sacn.sACNsender`, calls `.start()`,
   `.activate_output(universe)`, and sets the destination, multicast flag, and
   priority (`backend/dmx/sender.py:55-62`). **Network output infrastructure is
   live before FastAPI's lifespan has run.**
5. `uvicorn.run(app, host=..., port=...)` executes (`backend/main.py:156`).
   There is no `if __name__ == "__main__":` guard.

The consequence is that ordinary inspection, ASGI tooling, and test collection
are all unsafe. This is why every document in this repository forbids importing
`backend/main.py` as a validation step, and why milestone M1 exists.

Note also that imports are written as `from models.config import CONFIG` rather
than `from backend.models.config import ...`. These top-level imports resolve
only because `backend/` is on `sys.path`, which happens either through
`backend/__init__.py:1-7` — it inserts the package directory into `sys.path` as
an import-time side effect — or because the process was invoked with `backend/`
as its working directory. Neither is a canonical package import, and M1 will
need to decide whether to normalize the imports or pin the bootstrap.

## Scene-to-output flow

```
  Operator picks a full scene in the browser
                │
                ▼
  POST /api/apply/full-scene/{id}
                │
                ▼
  apply_full_scene_by_id()                       backend/routes/apply_full_scene.py
    ├── load_full_scenes()  → find FullScene     404 if missing
    ├── load_scenes()       → find Scene         404 if missing
    ├── set_full_scene(...) → writes the process-global _active dict
    │                         (NO LOCK)          backend/routes/active_scene.py
    ├── PLAYER.start_scene(ilda_scene)
    └── apply_preset_fn(preset_ids[0])
                │
                ▼
  _apply_preset_by_id()                          backend/routes/post.py:36
    ├── load_presets(), load_devices(), load_device_presets()
    │     └── load_devices() MAY MUTATE STORAGE  (see audit F9)
    ├── scene_based = [d for d in devices if control_type != "manual"]
    ├── for i, device in enumerate(scene_based):
    │       chosen = preset.device_presets[i]    ← POSITIONAL association
    │       match device preset on (device id AND preset id), normalized
    │       mismatch → skipped, not cross-applied
    │       device.active_channels = matched channel_values
    ├── save_devices(devices)  → devices.json    (non-atomic; refuses empty)
    └── if preset.ledfx_setting:
            LEDFXClient(...).set_active_scene()  synchronous, PUT timeout=5
                │
                ▼
  ─── the DMX thread observes the change only by re-reading devices.json ───
                │
                ▼
  SENDER.send() → MAPPER → DMXFrame → 512 channels → sACN → fixtures


  On each detected beat (browser mic → POST):
                │
                ▼
  advance_and_apply()                            backend/routes/active_scene.py:48
    ├── current_index = (current_index + 1) % len(preset_ids)   (NO LOCK)
    ├── apply_preset_fn(preset_ids[current_index])  → the chain above
    └── if PLAYER.is_beat_synced(): PLAYER.advance_beat()
                                       └── streams points → LoggingSink
```

The single most consequential structural fact on this diagram: **JSON
persistence is the live control bus between the API and the DMX output
thread.** There is no shared in-memory state. A preset application is
communicated to the output path by writing a file and letting the sender
re-read it. Output latency, and output correctness, therefore depend on disk
behavior and on write/read interleaving.

## Storage semantics

`backend/models/storage.py` is 43 lines and defines the entire persistence
layer.

Reads (`load_optional`, `load_optional_single`) catch exactly three exception
types — `FileNotFoundError`, `json.JSONDecodeError`, `ValidationError` — and
return `[]` or `None`. Validation failures print a message first; missing files
and malformed JSON are silent. Other `OSError` subclasses (permission denied,
I/O error) propagate to the caller. So the accurate statement is: *missing
files and malformed JSON may be silently converted to empty results,
validation failures print and return empty results, and some other OS errors
propagate.* It is not true that every storage error is swallowed.

Writes (`save`, `save_single`) open the destination path with `"w"` and
`json.dump` into it. No temporary file, no flush, no `fsync`, no `os.replace`,
no backup. A reader can observe a truncated file, and a crash mid-write
destroys the last valid version.

`routes/data.py:load_devices()` is a read operation that can write. If
`devices.json` is empty or unreadable it reconstructs devices from
`device_presets.json` and saves; it then appends a `haze` device if absent,
bootstraps `gigbar` and `keobin` if no scene-based device exists, and rewrites
`control_type` on those two if they are marked manual — persisting after each.
One mitigation exists: `save_devices()` refuses to write an empty list.

## Concurrency

Two threads and one asyncio task touch shared state.

- The **DMX daemon thread** runs `dmx_sender_loop`, calling `SENDER.send()` in
  a loop with no sleep, condition wait, or event wait. The only time-based
  logic throttles *error logging* to once per five seconds. The sacn library
  may throttle packet publication internally, but that does not pace the
  application loop, which continues to re-read and re-validate `devices.json`
  as fast as the CPU allows.
- **FastAPI sync route handlers** run in the worker threadpool and can execute
  concurrently. They read and mutate the module-global `_active` dict in
  `routes/active_scene.py` with no lock.
- The **status print loop** is an asyncio task that wakes every second and
  calls `asyncio.to_thread(_print_status_once)`, which loads devices and
  performs a LedFx HTTP GET.

`IldaPlayer` is the exception: it holds a `threading.Lock` and a stop event and
is the only correctly synchronized shared-state component in the codebase.

## Integration boundaries

**LedFx.** `LEDFXClient.__init__` builds `http://{config.server_host}:8888/api`
— it reuses the *FastAPI bind host* as the LedFx destination and hardcodes the
port. Setting `server_host` to `0.0.0.0` for LAN access therefore produces
`http://0.0.0.0:8888/api` as the LedFx target. There is no way to point Lights
at a LedFx instance on another machine, which is exactly what a split
WSL2/Windows deployment requires. Calls are synchronous `requests`;
`set_active_scene` passes `timeout=5`, while `get_scenes` and
`get_active_scene` pass no timeout at all. Because sync endpoints run in
FastAPI's worker pool and the status path uses `asyncio.to_thread`, these calls
do not directly block the asyncio event loop — but they can block worker
threads and accumulate outstanding requests.

**ILDA.** `IldaFrame.path` is an arbitrary string. `read_ild_file` does
`Path(path).read_bytes()` with no root containment, no extension check, and no
size limit, so absolute paths, traversal paths, and files of any size outside
any library root are all accepted. This must be closed before a real DAC is
attached.

**sACN.** The sender patches `SenderSocketUDP.send_packet` to swallow `OSError`
and log at most once per ten seconds, so an unreachable destination degrades to
periodic log lines rather than killing the send thread.

## Security posture

No authentication or authorization exists on any route — repository-wide
inspection found no `Depends`, no API key, and no bearer scheme. Every mutation
and output route is open to any client that can reach the port. CORS is
configured with wildcard origins, methods, and headers. `RUN.md` and
`BUILD_INSTRUCTIONS.md` both document setting `server_host` to `0.0.0.0` for
LAN access, which makes this a live exposure rather than a theoretical one.
CORS is a browser-side control and provides no protection against non-browser
clients.

---

# Part 2 — Creator design intent

## DESIGN INTENT

Everything in Part 2 comes from the creator's block diagram and Lighting Models
spreadsheet. None of it is a claim about current code. Where the current
implementation differs, the difference is noted.

The intended object model:

```
Scene
├── ID                          (string, the name)
├── Sensitivity                 (double — DMX audio sensitivity)
├── Preset List
│   └── Preset
│       ├── WLED / LedFx preset or scene   (string: name of LedFx scene to call)
│       └── DMX Preset List
│           └── DMX Preset
│               └── DMX Device Preset List
│                   └── DMX Device Preset
│                       ├── Device ID       (string)
│                       ├── Device order    (int — order in daisy chain)
│                       ├── Channel count   (int)
│                       └── Channel settings (list[int], per channel)
└── ILDA List
    └── ILDA frames             (iterated with BPM or other timing)
```

The block diagram additionally indicates:

- Explicit frontend / backend / hardware layer boundaries.
- Connector types: E1.31, class relationship, Ethernet, ILDA, WLED, API call.
- A **current DMX info** and a **current ILDA info** state holder, distinct
  from the stored scene and preset definitions.
- **E1.31 refresh approximately every 20 ms** (about 50 Hz).
- **ILDA transmitted by a separate mechanism**, not on the DMX timing path.
- **BPM / audio layering** influencing both the DMX and ILDA paths.
- A Lights scene corresponding to a **same-named LedFx scene**.
- **Pydantic classes** as the model layer, with an `Id` variable.
- A **callable model that is "just a packet of information on how audio
  influences render"** — an explicit, data-shaped audio-influence descriptor.

### Where the implementation diverges from the intent

| Design intent | Current implementation |
| --- | --- |
| `Scene.Sensitivity` | Does not exist on `Scene` |
| Nested DMX Preset → DMX Device Preset List | Flattened: `Preset.device_presets` is a flat `list[str]` of device-preset IDs, associated to devices *by position* |
| Explicit Device ID / order / channel count on the preset | Device identity lives on `DMXDevice`, not on the preset; the preset carries only `device` and `channel_values` |
| Distinct "current DMX info" state holder | No such component. Current DMX state *is* `devices.json` |
| E1.31 refresh every ~20 ms | No application-level pacing at all; the loop is unpaced |
| Audio-influence model as a data packet | No such model exists; beat handling is an index increment |
| Same-named Lights and LedFx scenes | Not enforced; `Preset.ledfx_setting` is a free string with no validation |

These divergences are the substance of milestones M5, M6, and M8.

---

# Part 3 — Target architecture

## TARGET ARCHITECTURE and PROPOSED

**The target architecture as a complete composition is not implemented.** No
composition root, catalog, runtime owner, scene engine, persistence service, or
preflight service exists. Components here are candidates, not a committed
design. Where a component's *shape* is genuinely undecided, it is marked
PROPOSED and appears as an open question in [decisions.md](decisions.md).

The live analyzer and renderer direction is now approved at its architectural
boundaries, while its implementation shape remains proposed. The canonical
description is [show_control_architecture.md](show_control_architecture.md);
this document does not duplicate it. In summary:

```text
system-audio loopback (preferred) / microphone / file / replay
        ↓
shared normalized features
        ↓
stabilized live musical state
        ↓
semantic cues
        ↓
LedFx compatibility / native WLED / fixture-aware DMX
```

That direction does not claim any of those new components exist. It also does
not make offline file analysis the primary mode: unpredictable Spotify
playback makes live capture party mode's runtime source of truth. The renderer
will grow incrementally beside LedFx, and all physical output remains subject
to explicit fixture patches, preflight, injectable transports, blackout, and
safety policy.

Three things below are precursor seams that **do** already exist in code, and
the diagram marks them. Do not read their presence as evidence that the
surrounding structure exists:

- **`PointSink` / `NullSink` / `LoggingSink`** — the output-adapter pattern is
  already realized for ILDA (`backend/ilda/sink.py`). It is the only place in
  the codebase where an output seam exists today.
- **Pydantic validation on read** — `load_optional` already validates through a
  `TypeAdapter` (`backend/models/storage.py`). What the persistence service adds
  is atomicity and typed read outcomes, not validation from scratch.
- **`LIGHTSAPP_DATA_DIR`** — the data-directory seam the composition root would
  build on already works (`backend/paths.py:22-30`).

```
┌──────────────────────────────────────────────────────────────────┐
│  Frontend (unchanged in kind — vanilla JS)                       │
└───────────────────────────┬──────────────────────────────────────┘
                            │ HTTP, authenticated, constrained CORS
┌───────────────────────────▼──────────────────────────────────────┐
│  API layer — FastAPI routers                                     │
│  Thin: validate request, call a service, shape a response        │
└───────────────────────────┬──────────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────────┐
│  COMPOSITION ROOT                                                │
│  Builds storage, config, adapters, runtime services, the app.    │
│  Selects a normal or a NO-HARDWARE composition.                  │
│  Owns lifecycle via FastAPI lifespan. Import has no side effects.│
└───┬───────────────┬──────────────────┬───────────────────────────┘
    │               │                  │
┌───▼──────────┐ ┌──▼───────────────┐ ┌▼─────────────────────────┐
│  CATALOG     │ │  RUNTIME OWNER   │ │  SCENE ENGINE            │
│  (PROPOSED   │ │                  │ │                          │
│   shape)     │ │ active scene     │ │ resolve references       │
│              │ │ scene GENERATION │ │ apply full scenes        │
│ devices      │ │ current index    │ │ advance on beat/timer    │
│ fixture      │ │ desired DMX state│ │ deterministic transitions│
│  profiles    │ │ desired LedFx    │ │ reject invalid refs      │
│ device       │ │ desired ILDA     │ └──┬───────────────────────┘
│  presets     │ │ status snapshots │    │
│ presets      │ │ synchronization  │    │ produces DESIRED STATE
│ scenes       │ │ error state      │    │ (in memory — not files)
│ full scenes  │ └──┬───────────────┘    │
│ ILDA defs    │    │                    │
│ app config   │    └────────────────────┘
└───┬──────────┘             │
    │                        │
┌───▼─────────────────┐ ┌────▼─────────────────────────────────────┐
│ PERSISTENCE SERVICE │ │  OUTPUT ADAPTERS                         │
│ atomic writes       │ │  (protocol-appropriate, NOT one          │
│  (tmp + os.replace) │ │   artificial common interface)           │
│ typed read outcomes │ │                                          │
│  Ok / Missing /     │ │  DmxTransport   real · null · recording  │
│  Invalid / Corrupt  │ │  LedFxClient    real · null · recording  │
│ migration/versioning│ │  PointSink      DAC  · null · logging    │
│ Windows file locks  │ │                  (already exists)        │
└─────────────────────┘ └──┬───────────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────────┐
│  PREFLIGHT SERVICE — runs BEFORE output is enabled               │
│  config · storage integrity · scene references · fixture patches │
│  channel bounds · output destinations · integration reachability │
└──────────────────────────────────────────────────────────────────┘
```

Constraints on this design, carried forward deliberately:

- **The catalog may not be one large `ShowCatalog`.** PROPOSED: a facade over
  smaller per-aggregate repositories is at least as likely to be correct. This
  is an open question, not a settled design.
- **The runtime owner must not become a God object.** If it accumulates
  responsibilities without bound, split it.
- **Adapters must not be forced into a shared interface.** DMX, LedFx, and ILDA
  are genuinely different protocols. Share only lifecycle concepts that are
  actually shared.
- **Fixture knowledge becomes data**, not branches in frontend and backend
  code: manufacturer, model, mode, channel count, channel definitions and
  ranges, named values, UI controls, manual vs scene-based behavior, universe,
  start address, and a profile version.
- **Runtime state leaves the persistence path.** Desired DMX state lives in
  memory; durable configuration is read outside the high-frequency loop; the
  sender wakes on an event or a monotonic clock at a configurable refresh rate.

## The DMX path, before and after

```
NOW                                    TARGET
───                                    ──────
route → save devices.json              route → runtime.set_desired(...)
             │ (disk)                              │ (memory + event)
             ▼                                     ▼
 thread: re-read + re-validate         thread: wake on event or tick
         every iteration, unpaced              monotonic pacing, configurable
             │                                     │
             ▼                                     ▼
        sacn sender                        DmxTransport (injectable)
                                             real │ null │ recording
```

The target removes the disk from the control path entirely. Persistence
continues to exist — it simply stops being the mechanism by which the API talks
to the output thread.
