# Current Sprint

**Status of this document:** canonical, and the shortest-lived document in this
set. Update it when a milestone completes.

## In progress: live-first renderer architecture documentation

**Branch:** `docs/live-renderer-architecture`
**Base HEAD:** `a33ecb3`
**Scope:** documentation only. No production code, tests, frontend code,
dependencies, transports, renderer classes, audio capture, Spotify
integration, or Mermaid diagrams.

This increment records a clarified primary use case: Lights normally runs at
parties with unpredictable Spotify playback and cannot assume the original file
is available. It updates the proposed show-control programme without changing
the stabilization milestone order.

### Definition of done

- [x] Required architecture and implementation context inspected
- [x] Live system-audio capture established as the preferred party source
- [x] Microphone fallback and optional offline analysis distinguished
- [x] Shared normalized feature and live musical-state boundaries documented
- [x] Semantic cue and fixture-rendering layers documented
- [x] LedFx compatibility and incremental native WLED/DMX migration documented
- [x] Runtime budgets, transition handling, and deterministic replay documented
- [x] Safety boundaries preserved and expanded
- [x] Roadmap split into Phase 3A, 3B, and 3C
- [x] Accepted decisions D-13 through D-20 recorded
- [x] Documentation consistency and link validation

### Subsequent documentation increment

Mermaid diagrams may translate the approved text architecture after this
branch. They are not part of this sprint and must not decide unresolved
implementation choices.

---

## Next: M1 — Safe import and lifecycle

**Branch to create:** `architecture/safe-import-boundary`

This is the first production-code branch. Its scope is deliberately narrow —
resist every temptation to widen it, because a large first branch is
unreviewable and this one establishes the review pattern for everything after.

### Files in scope

- `backend/main.py`
- `backend/routes/data.py` — **only** to remove import-time directory creation
- `tests/test_import_safety.py` (new)
- `tests/test_startup_lifecycle.py` (new)
- minimal dev-only pytest setup

### Explicitly out of scope

Storage redesign · fixture-bootstrap removal · DMX pacing · runtime-state
separation · authentication · CORS changes · LedFx redesign · AI cleanup · DMX
value validation · ILDA path validation.

Every one of these is a real defect with a milestone of its own. None of them
belongs in this branch.

### Acceptance criteria

All fourteen must hold before the branch is considered complete.

1. Importing the application terminates without creating files or directories.
2. Import does not construct or start sACN.
3. Import does not start worker threads.
4. Import does not call LedFx.
5. Import does not invoke Uvicorn.
6. Running the entry module deliberately still resolves the configured host and
   port and starts Uvicorn.
7. FastAPI lifespan constructs exactly one sender.
8. Lifespan starts and stops the DMX worker.
9. Lifespan stops the sender safely.
10. Tests use fakes and cannot contact physical output.
11. Existing API paths and static frontend mounts remain present.
12. Python modules parse successfully.
13. Focused tests pass against isolated storage.
14. Native-Windows validation requirements remain documented.

### What "verified" means for criteria 1–5

These are the criteria most easily claimed without evidence. Each needs a test
that would *fail today*: import the module in a subprocess with
`LIGHTSAPP_DATA_DIR` pointed at an empty temporary directory, then assert the
directory is still empty, no thread was started, no socket was opened, and the
process exited. Writing these tests before the fix is the point — they are the
characterization tests that prove F1, F2, and F3 were real and are gone.

### Known obstacle

Modules import as `from models.config import ...` rather than
`from backend.models.config import ...`. Those top-level imports resolve only
because `backend/` is on `sys.path`, and it gets there one of two ways:
`backend/__init__.py:1-7` inserts the package directory into `sys.path` as an
import-time side effect, or the process is invoked with `backend/` as the
working directory. Neither is a canonical package import.

A test that imports the application therefore inherits a `sys.path` mutation it
did not ask for. Either normalize the imports as part of this branch, or accept
the bootstrap and pin the behavior with a test. Decide which before starting —
normalizing imports touches many files and may deserve its own branch.

### Blocked on

Nothing. M1 can begin as soon as M0 is audited. OQ-1 is a nonblocking
follow-up.
