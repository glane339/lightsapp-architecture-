# Quick Start Guide - Building Portable LightsApp

> **STATUS: PARTIALLY STALE — build documentation, retained deliberately.**
>
> This file predates the architecture fork. The PyInstaller build steps are
> still the repository's only record of how a Windows executable is produced,
> so it is kept.
>
> **Everything below this banner is historical and unverified.** It has not
> been exercised against the current tree, and no claim in it carries an
> evidence label.
>
> **The corrections in this banner are separate, and are CODE-INSPECTED ONLY —
> each was checked against the current tree:**
>
> - The "What Was Changed" checklist describes work done in an earlier project
>   phase. It is a historical record, not a description of current state.
> - It references `installer.iss`, which is **not tracked in this repository**
>   (`git ls-files`). `build.bat`, `build_exe.py`, and `lightsapp.spec` are
>   tracked.
> - **The build assumes the repository root is the working directory.**
>   `build.bat` does not anchor itself — it has no `cd /d "%~dp0"` — and
>   resolves `.venv\Scripts\python.exe` and `build_exe.py` relatively.
>   `build_exe.py:14-18` then passes the bare spec name `'lightsapp.spec'` to
>   PyInstaller. Double-clicking `build.bat` from Explorer happens to work
>   because Explorer sets the working directory to the file's folder; invoking
>   it from anywhere else does not.
> - Builds must run on native Windows. See
>   [docs/platform_support.md](docs/platform_support.md).
> - **Step 3, "Test it: double-click `LightsApp.exe`", is not a packaging smoke
>   test.** The executable runs `backend/main.py`, which constructs and starts
>   an sACN sender at import and polls LedFx from its status loop (F1, F3).
>   Treat launching it as a hardware- and network-affecting action until a
>   verified no-hardware composition exists (M1/M2).
>
> For current architecture and policy, start at
> [docs/project_overview.md](docs/project_overview.md).

## Fastest Way to Build

1. **Double-click `build.bat`** - This will automatically install PyInstaller if needed and build the executable

2. **Find your executable**: `dist\LightsApp.exe`

3. **Test it**: Double-click `LightsApp.exe` in the `dist` folder

## For Flash Drive (Portable)

Simply copy the entire `dist` folder to your flash drive. The app will run from anywhere!

```
[Flash Drive]\
└── dist\
    ├── LightsApp.exe
    ├── backend\
    │   └── data\
    └── frontend\
```

## Creating an Installer

1. Download **Inno Setup** from: https://jrsoftware.org/isdl.php
2. Install Inno Setup
3. Open `installer.iss` in Inno Setup Compiler
4. Click "Build" → "Compile"
5. Find installer at: `installer_output\LightsApp_Setup.exe`

## What Was Changed

- ✅ Updated `main.py` to detect portable paths (flash drive support)
- ✅ Updated `routes/data.py` for portable paths
- ✅ Updated `dmx/sender.py` for portable paths
- ✅ Created PyInstaller spec file (`lightsapp.spec`)
- ✅ Created build script (`build_exe.py`)
- ✅ Created Windows batch file (`build.bat`)
- ✅ Created Inno Setup installer script (`installer.iss`)

## Troubleshooting

**Executable won't start?**
- Run from command line to see errors: `dist\LightsApp.exe`
- Check that `backend\data\config.json` exists

**Missing files?**
- Rebuild: `python build_exe.py --clean`
- Or just run `build.bat` again

**Need help?**
- See `BUILD_INSTRUCTIONS.md` for detailed information
