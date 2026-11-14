#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ios_build_root="$HOME/Library/Developer/FiestaBoard/ios"
ios_slice="${IOS_SLICE:-i0}"
[[ "$ios_slice" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid IOS_SLICE' >&2; exit 2; }
mkdir -p "$ios_build_root/clang" "$ios_build_root/results/$ios_slice"
export CLANG_MODULE_CACHE_PATH="$ios_build_root/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ios_build_root/clang"
case "${1:-all}" in
  packages|all)
    for package in FiestaBoardKit FiestaBoardAppState FiestaBoardDocuments FiestaBoardEditorState; do
      swift test ${SWIFTPM_DISABLE_SANDBOX:+--disable-sandbox} --package-path "Packages/$package" --scratch-path "$ios_build_root/swiftpm-build/$ios_slice/$package" --cache-path "$ios_build_root/swiftpm-cache" --config-path "$ios_build_root/swiftpm-config" --security-path "$ios_build_root/swiftpm-security"
    done
    [[ "${1:-all}" != packages ]] || exit 0
    ;;
  simulators) ;;
  *) echo 'Usage: scripts/test.sh [all|packages|simulators]' >&2; exit 2 ;;
esac
for model in 'iPhone 17' 'iPad Air 11-inch (M4)'; do
  udid=$(xcrun simctl list devices available --json | python3 scripts/select-ios-simulator.py "$model")
  result="$ios_build_root/results/$ios_slice/$(date +%s)-$udid.xcresult"
  xcodebuild -project FiestaBoard.xcodeproj -scheme FiestaBoard \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$ios_build_root/dd-$ios_slice" \
    -clonedSourcePackagesDirPath "$ios_build_root/spm" \
    -resultBundlePath "$result" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -only-testing:FiestaBoardAppTests -only-testing:FiestaBoardRenderTests \
    -only-testing:FiestaBoardUITests/LaunchUITests \
    CODE_SIGNING_ALLOWED=NO test
done
