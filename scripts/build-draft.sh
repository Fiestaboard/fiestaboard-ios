#!/bin/bash
set -euo pipefail
# Build the committed project. Never regenerate it or change the user's signing Team.
draft_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$draft_root"
case "${1:-simulator}" in
  simulator) draft_destination='generic/platform=iOS Simulator'; draft_products='Debug-iphonesimulator'; draft_action='build' ;;
  device) draft_destination='generic/platform=iOS'; draft_products='Debug-iphoneos'; draft_action='build' ;;
  archive) draft_destination='generic/platform=iOS'; draft_products='Release-iphoneos'; draft_action='archive' ;;
  *) echo 'Usage: scripts/build-draft.sh [simulator|device|archive] [live|demo]' >&2; exit 2 ;;
esac
case "${2:-live}" in
  live) draft_scheme='FiestaBoard' ;;
  demo) draft_scheme='FiestaBoard Demo' ;;
  *) echo 'Scheme must be live or demo' >&2; exit 2 ;;
esac
if [[ $# -gt 2 ]]; then echo 'Too many arguments' >&2; exit 2; fi
draft_output="$HOME/Library/Developer/FiestaBoard/ios"
mkdir -p "$draft_output/clang"
draft_build_args=(-project FiestaBoard.xcodeproj -scheme "$draft_scheme"
  -destination "$draft_destination" -derivedDataPath "$draft_output/dd-build"
  -clonedSourcePackagesDirPath "$draft_output/spm")
if [[ "$draft_action" == archive ]]; then
  draft_build_args+=(-archivePath "$draft_output/FiestaBoard.xcarchive")
fi
env CLANG_MODULE_CACHE_PATH="$draft_output/clang" \
  xcodebuild "${draft_build_args[@]}" CODE_SIGNING_ALLOWED=NO "$draft_action"
if [[ "$draft_action" == archive ]]; then
  printf '\nUnsigned validation archive: %s/FiestaBoard.xcarchive\n' "$draft_output"
else
  printf '\nUnsigned draft app: %s/dd-build/Build/Products/%s/FiestaBoard.app\n' "$draft_output" "$draft_products"
fi
