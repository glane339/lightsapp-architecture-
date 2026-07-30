#!/usr/bin/env bash
set -euo pipefail

if ! repository_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf 'Error: scripts/context.sh must be run from inside a Git worktree.\n' >&2
    exit 1
fi

branch="$(git -C "$repository_root" branch --show-current)"
if [[ -z "$branch" ]]; then
    branch="(detached HEAD)"
fi

python_executable="$(command -v python 2>/dev/null || true)"
if [[ -n "$python_executable" ]]; then
    python_version="$(python --version 2>&1)"
else
    python_executable="(not found on PATH)"
    python_version="(unavailable)"
fi

printf 'Project: LightsApp Architecture\n'
printf 'Repository root: %s\n' "$repository_root"
printf 'Current branch: %s\n' "$branch"
printf 'Git status summary:\n'
git_status="$(git -C "$repository_root" status --short)"
if [[ -n "$git_status" ]]; then
    printf '%s\n' "$git_status"
else
    printf '  clean\n'
fi

printf 'Configured remotes:\n'
remotes="$(git -C "$repository_root" remote -v)"
if [[ -n "$remotes" ]]; then
    printf '%s\n' "$remotes"
else
    printf '  none\n'
fi

printf 'Python version: %s\n' "$python_version"
printf 'Python executable: %s\n' "$python_executable"
printf 'Active virtual environment: %s\n' "${VIRTUAL_ENV:-(unset)}"

if [[ -n "${LIGHTSAPP_DATA_DIR:-}" ]]; then
    printf 'LIGHTSAPP_DATA_DIR: %s\n' "$LIGHTSAPP_DATA_DIR"
else
    printf 'LIGHTSAPP_DATA_DIR: (unset)\n'
    printf 'WARNING: Set LIGHTSAPP_DATA_DIR to an isolated path such as "$PWD/.local-data" before development or testing.\n' >&2
fi

printf 'RUNTIME WARNING: Running or importing backend/main.py may initialize runtime data, start sACN/DMX behavior, and launch Uvicorn.\n'
printf 'This context script does not launch the application, import backend/main.py, activate an environment, create data, or contact hardware.\n'
