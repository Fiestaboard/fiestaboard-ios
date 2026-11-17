#!/usr/bin/env bash
# Supplemental wire audit only; does not replace original Docker-recorded fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."
cx_repo="${CX_HUB_REPO:-/Volumes/ExtHD/workspace/fb-wt/cx-v11fix2}"
cx_commit="${CX_HUB_COMMIT:-f47da6e4e764fc2826f396210f013e45dc1a7fd8}"
[[ "$cx_commit" =~ ^[a-f0-9]{40}$ ]] || exit 2
cx_out="${CX_HOME_OUT:-Tests/Fixtures/Home/HostSupplement}"
cx_python="$HOME/Library/Developer/FiestaBoard/ios/cx-iosnext5-i7-hub-venv/bin/python"
[[ -x "$cx_python" ]] || { echo 'Create the isolated, documented host dependency environment first.' >&2; exit 2; }
cx_tmp=$(mktemp -d /private/tmp/cx-iosnext5-i7-host.XXXXXX)
trap 'rm -rf "$cx_tmp"' EXIT
mkdir "$cx_tmp/hub" "$cx_tmp/data"
git -C "$cx_repo" archive "$cx_commit" src plugins assets staff-picks package.json plugin-registry.json outputs.lock.json requirements.txt | tar -x -C "$cx_tmp/hub"
mkdir -p "$cx_out"
CX_FIXTURE_OUT="$PWD/$cx_out" CX_DATA_DIR="$cx_tmp/data" \
CX_REQUEST_MANIFEST="$PWD/Tests/Fixtures/Home/requests-host.json" \
CX_RECORDING_METHOD='Host isolated uv environment; immutable runtime source git archive; real FastAPI HTTP boundary; supplemental not Docker C5 proof' \
CX_HUB_COMMIT="$cx_commit" PYTHONPATH="$cx_tmp/hub" "$cx_python" scripts/record-home-fixtures.py
UV_CACHE_DIR="$HOME/Library/Developer/FiestaBoard/ios/cx-iosnext5-i7-uv-cache" uv pip freeze --python "$cx_python" > "$cx_out/environment.txt"
