# Platform Support: WSL2 Development, Native Windows Validation

**Status of this document:** canonical policy.

Lights is developed on WSL2 and deployed on native Windows. These are not
interchangeable. The single governing rule:

> **WSL2 testing never verifies physical hardware behavior.** No claim of
> HARDWARE VERIFIED may be made from a WSL2 result, under any circumstances.

## The split

```
┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
│  WSL2  —  PRIMARY DEVELOPMENT       │   │  NATIVE WINDOWS  —  DEPLOYMENT      │
│                                     │   │  AND HARDWARE VALIDATION            │
│  Cursor / IDE                       │   │                                     │
│  .venv/bin/python  (3.12.1)         │   │  PyInstaller build machine          │
│  LIGHTSAPP_DATA_DIR=$PWD/.local-data│   │  real rig on the local network      │
│                                     │   │                                     │
│  ✓ editing                          │   │  ✓ PyInstaller Windows executable   │
│  ✓ documentation                    │   │  ✓ Windows launch scripts (.bat)    │
│  ✓ unit tests                       │   │  ✓ path behavior                    │
│  ✓ integration tests, null/fake HW  │   │  ✓ file-lock behavior               │
│  ✓ linting                          │   │  ✓ atomic replacement behavior      │
│  ✓ type checking                    │   │  ✓ process shutdown / Ctrl+C        │
│  ✓ JSON and schema validation       │   │  ✓ daemon-thread behavior           │
│  ✓ scene and preset logic           │   │  ✓ UDP interface selection          │
│  ✓ DMX frame construction           │   │  ✓ sACN multicast/unicast           │
│  ✓ ILDA parsing                     │   │  ✓ Windows Defender Firewall        │
│  ✓ mocked LedFx behavior            │   │  ✓ physical DMX fixtures            │
│  ✓ FastAPI dev — ONLY after a safe  │   │  ✓ real LedFx/WLED deployment       │
│    no-hardware mode exists (M1/M2)  │   │  ✓ browser microphone, host browser │
│                                     │   │  ✓ future USB/Ethernet laser DACs   │
│  ✗ physical fixtures                │   │  ✓ blackout, watchdog, interlock,   │
│  ✗ real sACN transmission           │   │    emergency stop procedures        │
│  ✗ real LedFx/WLED                  │   │                                     │
│  ✗ laser output                     │   │  ⚠ This is the ONLY environment     │
│  ✗ Windows file locks / paths       │   │    that can produce a               │
│  ✗ firewall behavior                │   │    HARDWARE VERIFIED claim.         │
│  ✗ PyInstaller Windows builds       │   │                                     │
└─────────────────────────────────────┘   └─────────────────────────────────────┘
         │                                              ▲
         │  hardware-free CI runs on BOTH               │
         └──────────────────────────────────────────────┘
              Windows executables are built ON Windows
```

## Why the split is real, not bureaucratic

Four categories of behavior genuinely differ, and each has bitten projects of
this shape before:

**Networking.** WSL2 sits behind a virtual network adapter. UDP interface
selection, sACN multicast group membership, and broadcast behavior do not
match the Windows host. A successful sACN send from WSL2 says nothing about
whether packets reach a fixture on the physical LAN.

**Filesystem semantics.** Windows file locking is mandatory where Linux is
advisory, and `os.replace` over an open file behaves differently. This matters
directly for milestone M3 — the atomic-write strategy must be validated on
Windows, because that is where it can actually fail.

**Firewall.** Windows Defender Firewall prompts on first bind and can silently
drop UDP. There is no WSL2 equivalent to test against.

**Packaging.** PyInstaller produces a Windows executable only when run on
Windows. `backend/main.py:20-27` already branches on `sys.frozen` for portable
path resolution, and that branch is only exercisable in a real frozen build.

## Cross-platform engineering principles

These apply to all code written in this repository:

- Use `pathlib`. Never build paths with string concatenation or hardcoded
  slash styles.
- Do not rely on case-insensitive imports or filenames.
- Do not depend on `backend/` being the working directory, and do not depend on
  `sys.path` mutation to make imports resolve. **This is currently violated** —
  modules import as `from models.config import ...` rather than
  `from backend.models.config import ...`. Those top-level imports resolve only
  because `backend/` is on `sys.path`, which happens either through
  `backend/__init__.py:1-7` inserting it as an import-time side effect, or
  because the process was invoked with `backend/` as its working directory.
  Neither is a canonical package import. Milestone M1 should address it.
- Prefer package execution and canonical Python entrypoints over shell-only
  workflows.
- Prefer Python validation scripts to shell scripts, with thin `.sh` and `.ps1`
  wrappers only where they genuinely help.
- Use temporary directories in portable tests. Never hardcode `/tmp`.
- Keep the FastAPI bind host separate from the LedFx destination host. This is
  currently violated — see F17 in [audit_findings.md](audit_findings.md) — and
  it is precisely what makes a split WSL2/Windows deployment inexpressible
  today.
- Run hardware-free CI on both Linux and Windows.
- Build Windows executables on Windows.

## Deployment combinations to support

Milestone M7 must make all three expressible in configuration:

| Lights runs on | LedFx runs on | Currently expressible? |
| --- | --- | --- |
| Windows | same Windows host | Yes, incidentally — only because both resolve to the same host |
| WSL2 | Windows host | **No** — F17 forces the LedFx host to equal the FastAPI bind host |
| Windows or WSL2 | another LAN machine | **No** — same reason |

## Data directory by platform

`backend/paths.py:22-30`, VERIFIED CURRENT BEHAVIOR:

| Condition | Data directory |
| --- | --- |
| `LIGHTSAPP_DATA_DIR` set | that path, resolved |
| Windows, unset | `%LOCALAPPDATA%\LightsApp\data` |
| Unix/WSL2, unset | `~/.local/share/LightsApp/data` |

Always export `LIGHTSAPP_DATA_DIR="$PWD/.local-data"` for development. The real
user data directory must never be read, written, migrated, or tested against.

## Current hardware-safe validation commands

These are the only commands currently established as safe. None imports
`backend/main.py`. Run them from the repository root; all paths below are
repository-relative.

WSL2 / Linux:

```bash
export LIGHTSAPP_DATA_DIR="$PWD/.local-data"

# environment context (does not launch anything)
./scripts/context.sh

# dependency import check — installed packages only
.venv/bin/python -c "import fastapi, uvicorn, pydantic, requests, sacn; print('Core imports passed')"

# ILDA reader smoke check
.venv/bin/python -m backend.ilda.test_reader

# documentation and diff hygiene
git status --short
git diff --check
```

Native Windows (PowerShell):

```powershell
$env:LIGHTSAPP_DATA_DIR = Join-Path $PWD ".local-data"

# scripts/context.sh is Bash-only; there is no PowerShell equivalent yet

.\.venv\Scripts\python.exe -c "import fastapi, uvicorn, pydantic, requests, sacn; print('Core imports passed')"
.\.venv\Scripts\python.exe -m backend.ilda.test_reader

git status --short
git diff --check
```

The ILDA smoke check runs as a package module because importing `backend` puts
`backend/` on `sys.path` (`backend/__init__.py:1-7`), which is what makes its
top-level `from ilda.reader import ...` resolve. That bootstrap is itself a
defect the M1 branch must decide about — see
[current_sprint.md](current_sprint.md).

**Launching the packaged executable is not on this list and must not be added
to it.** `dist\LightsApp.exe` runs `backend/main.py`, which constructs and
starts an sACN sender at import and polls LedFx from its status loop. It is a
hardware- and network-affecting action, not a packaging smoke test, until a
verified no-hardware composition exists (M1/M2).

After M2, this list is replaced by a pytest suite running under a no-hardware
composition, on both Linux and Windows CI.

## Native-Windows validation checklist

No milestone touching output, packaging, or persistence may be called complete
until the relevant rows are exercised on native Windows against the real rig.
This checklist is currently **entirely unverified** — nothing in this
repository carries a HARDWARE VERIFIED label.

| Area | Milestone | Verified |
| --- | --- | --- |
| PyInstaller executable builds (native Windows only — never from WSL2) | M1 | ☐ |
| Packaged executable launches — hardware/network-affecting, treat as a rig test | M1 | ☐ |
| Windows launcher scripts work from any directory | M1 | ☐ |
| Atomic replacement survives Windows file locking | M3 | ☐ |
| Ctrl+C and process shutdown release the sACN sender | M1 | ☐ |
| Daemon thread terminates cleanly on shutdown | M1, M5 | ☐ |
| UDP interface selection reaches the correct adapter | M5 | ☐ |
| sACN unicast reaches physical fixtures | M5 | ☐ |
| sACN multicast reaches physical fixtures | M5 | ☐ |
| Windows Defender Firewall permits output | M9 | ☐ |
| Physical DMX fixtures respond as expected | M5 | ☐ |
| Real LedFx/WLED deployment responds | M7 | ☐ |
| Browser microphone works in the host browser | M6 | ☐ |
| Laser DAC output, with interlock and e-stop | M11 | ☐ |
| Blackout and watchdog procedures | M11 | ☐ |
