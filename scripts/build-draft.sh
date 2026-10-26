#!/bin/bash
set -euo pipefail
# No live server, signing credential, simulator boot, or global cache change is needed.
draft_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$draft_root"
case "${1:-simulator}" in
  simulator) draft_destination='generic/platform=iOS Simulator'; draft_products='Debug-iphonesimulator' ;;
  device) draft_destination='generic/platform=iOS'; draft_products='Debug-iphoneos' ;;
  *) echo 'Usage: scripts/build-draft.sh [simulator|device]' >&2; exit 2 ;;
esac
mkdir -p "$draft_root/.build/clang"
if command -v xcodegen >/dev/null 2>&1; then xcodegen generate; fi
env CLANG_MODULE_CACHE_PATH="$draft_root/.build/clang" \
  xcodebuild -project FiestaBoard.xcodeproj -scheme FiestaBoard \
  -destination "$draft_destination" -derivedDataPath "$draft_root/.build/draft-derived" \
  CODE_SIGNING_ALLOWED=NO build
printf '\nDraft app: %s/.build/draft-derived/Build/Products/%s/FiestaBoard.app\n' "$draft_root" "$draft_products"
