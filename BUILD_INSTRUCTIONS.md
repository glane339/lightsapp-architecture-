# Building LightsApp as Standalone Executable and Installer

> **STATUS: PARTIALLY STALE — build documentation, retained deliberately.**
>
> This file predates the architecture fork and is the repository's most
> detailed record of the Windows packaging process, so it is kept.
>
> **Everything below this banner is historical and unverified.** It has not
> been exercised against the current tree, and no claim in it carries an
> evidence label.
>
> **The corrections in this banner are separate, and are CODE-INSPECTED ONLY —
> each was checked against the current tree:**
>
> - **"Python 3.10+" is outdated.** This fork requires **3.12.1**.
> - **`installer.iss` is not tracked in this repository.** The Inno Setup
>   section cannot be followed as written.
> - **The build assumes the repository root is the working directory.**
>   `build.bat` does not anchor itself with `cd /d "%~dp0"`, and
>   `build_exe.py:14-18` passes the bare spec name `'lightsapp.spec'` to
>   PyInstaller. Run both from the repository root.
> - **Step 3 is not a build step.** "Verify it starts correctly" and "check that
>   DMX and LedFx functionality works" launch the real application: the
>   executable runs `backend/main.py`, which constructs and starts an sACN
>   sender at import and polls LedFx from its status loop (F1, F3 in
>   [docs/audit_findings.md](docs/audit_findings.md)). Treat launching the
>   executable as a hardware- and network-affecting action, requiring native
>   Windows and the real rig, until a verified no-hardware composition exists
>   (M1/M2). It can never be performed from WSL2 — see
>   [docs/platform_support.md](docs/platform_support.md).
> - **The `0.0.0.0` guidance exposes an unauthenticated API.** No route has
>   authentication and CORS is wildcarded (F12, F13). It also produces a
>   nonportable LedFx destination: `server_host` is reused as the LedFx host,
>   conflating the FastAPI *bind* address with an outbound *destination*
>   address, which makes remote or split-host LedFx configuration impossible to
>   express (F17). Whether `http://0.0.0.0:8888` also fails locally is
>   client- and OS-dependent and is not asserted here.
>
> For current architecture and policy, start at
> [docs/project_overview.md](docs/project_overview.md).

This guide explains how to create a portable `.exe` file and installer for LightsApp that can run from a flash drive.

## Prerequisites

1. **Python 3.10+** installed on your build machine
2. **PyInstaller** - Install with: `pip install pyinstaller`
3. **Inno Setup** (for creating installer) - Download from [jrsoftware.org](https://jrsoftware.org/isdl.php)

## Step 1: Install Dependencies

```bash
pip install -r requirements.txt
pip install pyinstaller
```

## Step 2: Build the Executable

Run the build script:

```bash
python build_exe.py
```

This will:
- Create a `dist` folder containing `LightsApp.exe`
- Bundle all Python dependencies
- Include the `backend/data` directory with all JSON files
- Include the entire `frontend` directory

The executable will be located at: `dist\LightsApp.exe`

## Step 3: Test the Executable

Before creating the installer, test the executable:

1. Navigate to the `dist` folder
2. Double-click `LightsApp.exe`
3. Verify it starts correctly and opens the web interface
4. Check that DMX and LedFx functionality works

## Step 4: Create the Installer (Optional)

If you want to create an installer:

1. **Install Inno Setup** from [jrsoftware.org](https://jrsoftware.org/isdl.php)

2. **Open Inno Setup Compiler**

3. **Open the script**: File → Open → Select `installer.iss`

4. **Build the installer**: Build → Compile

5. The installer will be created in `installer_output\LightsApp_Setup.exe`

## Step 5: Portable Flash Drive Setup

For a portable version that runs directly from a flash drive (no installer needed):

1. Copy the entire `dist` folder to your flash drive
2. The folder structure should be:
   ```
   [Flash Drive]\
   ├── LightsApp.exe
   ├── backend\
   │   └── data\
   │       ├── config.json
   │       ├── devices.json
   │       ├── device_presets.json
   │       ├── presets.json
   │       └── scenes.json
   └── frontend\
       ├── index.html
       ├── css\
       ├── js\
       └── html\
   ```

3. Double-click `LightsApp.exe` from the flash drive to run

## Important Notes

- **Configuration**: The `backend/data/config.json` file must exist and be properly configured before running
- **Network Access**: If you want to access from other devices on the network, set `server_host` to `"0.0.0.0"` in `config.json`
- **Firewall**: Windows Firewall may prompt for network access - allow it for DMX functionality
- **Portable Paths**: The application automatically detects if it's running from a portable location and adjusts paths accordingly

## Troubleshooting

### Executable won't start
- Check that all files are present in the `dist` folder
- Run from command line to see error messages: `dist\LightsApp.exe`
- Ensure `backend/data/config.json` exists and is valid

### Missing dependencies
- Rebuild with `--clean` flag: `pyinstaller lightsapp.spec --clean`
- Check that all imports in `lightsapp.spec` are correct

### Frontend not loading
- Verify `frontend` folder is included in `dist`
- Check that paths in `main.py` are correct for portable mode

### DMX not working
- Verify network configuration in `config.json`
- Check Windows Firewall settings
- Ensure ethernet cable is connected

## File Structure After Build

```
dist/
├── LightsApp.exe          # Main executable
├── backend/
│   ├── data/              # All JSON config files
│   └── [Python modules]  # Bundled Python code
└── frontend/              # All HTML/CSS/JS files
```

## Updating the Build

To rebuild after making changes:

1. Make your code changes
2. Run `python build_exe.py` again
3. Test the new executable
4. Rebuild installer if needed
