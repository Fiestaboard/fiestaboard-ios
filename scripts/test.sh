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
# CI selects one exact device and a bounded suite; local defaults retain the full run.
ios_test_shard="${IOS_TEST_SHARD:-all}"
case "$ios_test_shard" in all|units|ui-a|ui-b|ui-c|ui-d|ui-e|ui-f|ui-g|ui-h) ;; *) echo 'Invalid IOS_TEST_SHARD' >&2; exit 2 ;; esac
models=('iPhone 17' 'iPad Air 11-inch (M4)')
if [[ -n "${IOS_TEST_MODEL:-}" ]]; then
  case "$IOS_TEST_MODEL" in
    'iPhone 17'|'iPad Air 11-inch (M4)') models=("$IOS_TEST_MODEL") ;;
    *) echo 'Invalid IOS_TEST_MODEL' >&2; exit 2 ;;
  esac
fi
ui_filters=()
if [[ "$ios_test_shard" == ui-* ]]; then
  while IFS= read -r class; do
    ui_filters+=("-only-testing:FiestaBoardUITests/$class")
  done < <(python3 -c 'import json,sys; print("\n".join(json.load(open("scripts/ios-ui-shards.json"))[sys.argv[1]]))' "$ios_test_shard")
  [[ ${#ui_filters[@]} -gt 0 ]] || { echo 'Empty UI shard' >&2; exit 2; }
fi
# Own a loopback fixture process; never reuse or terminate another session's server.
fixture_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
FIXTURE_PORT="$fixture_port" python3 Tests/UITests/fixture_server.py > "$ios_build_root/results/$ios_slice/fixture.log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
export TEST_RUNNER_FIXTURE_PORT="$fixture_port"
curl --fail --retry 10 --retry-connrefused --retry-delay 1 "http://127.0.0.1:$fixture_port/ready"
simulator_failed=0
for model in "${models[@]}"; do
  udid=$(xcrun simctl list devices available --json | python3 scripts/select-ios-simulator.py "$model")
  xcrun simctl bootstatus "$udid" -b
  # A fresh simulator otherwise presents the first-use slide-to-type sheet over the editor.
  xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool YES
  args=(-project FiestaBoard.xcodeproj -scheme FiestaBoard
    -destination "platform=iOS Simulator,id=$udid"
    -derivedDataPath "$ios_build_root/dd-$ios_slice"
    -clonedSourcePackagesDirPath "$ios_build_root/spm"
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
    CODE_SIGN_IDENTITY=-)
  # Run unit/renderer checks before UI automation puts sustained load on the device.
  result="$ios_build_root/results/$ios_slice/$(date +%s)-$udid"
  if [[ "$ios_test_shard" == ui-* ]]; then
    # Each CI shard builds its own test bundle on its runner; no cross-runner products.
    if ! xcodebuild "${args[@]}" "${ui_filters[@]}" -resultBundlePath "$result-$ios_test_shard.xcresult" test; then simulator_failed=1; fi
  elif xcodebuild "${args[@]}" -skip-testing:FiestaBoardUITests -resultBundlePath "$result-units.xcresult" test; then
    if [[ "$ios_test_shard" == all ]]; then
      if ! xcodebuild "${args[@]}" -only-testing:FiestaBoardUITests -resultBundlePath "$result-ui.xcresult" test-without-building; then simulator_failed=1; fi
    fi
  else
    simulator_failed=1
  fi
  # Release this job's selected simulator before starting the next device/archive.
  if xcrun simctl shutdown "$udid"; then
    :
  else
    shutdown_status=$?
    # The device may already be shut down. Accept only a fresh, exact-device
    # confirmation; a failed query or any other state retains the cleanup error.
    if xcrun simctl list devices --json | python3 -c '
import json, sys
devices = [device for group in json.load(sys.stdin)["devices"].values() for device in group
           if device.get("udid") == sys.argv[1]]
sys.exit(0 if len(devices) == 1 and devices[0].get("state") == "Shutdown" else 1)
' "$udid"; then
      echo "Selected simulator $udid is already shut down."
    else
      exit "$shutdown_status"
    fi
  fi
done
exit "$simulator_failed"
