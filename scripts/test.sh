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
# Own a loopback fixture process; never reuse or terminate another session's server.
fixture_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
FIXTURE_PORT="$fixture_port" python3 Tests/UITests/fixture_server.py > "$ios_build_root/results/$ios_slice/fixture.log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
export TEST_RUNNER_FIXTURE_PORT="$fixture_port"
curl --fail --retry 10 --retry-connrefused --retry-delay 1 "http://127.0.0.1:$fixture_port/ready"
for model in 'iPhone 17' 'iPad Air 11-inch (M4)'; do
  udid=$(xcrun simctl list devices available --json | python3 scripts/select-ios-simulator.py "$model")
  xcrun simctl bootstatus "$udid" -b
  args=(-project FiestaBoard.xcodeproj -scheme FiestaBoard
    -destination "platform=iOS Simulator,id=$udid"
    -derivedDataPath "$ios_build_root/dd-$ios_slice"
    -clonedSourcePackagesDirPath "$ios_build_root/spm"
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
    CODE_SIGNING_ALLOWED=NO)
  # XCTest executes suites serially with parallel testing disabled. One invocation
  # per device avoids restarting the simulator service for every test class.
  result="$ios_build_root/results/$ios_slice/$(date +%s)-$udid.xcresult"
  xcodebuild "${args[@]}" -resultBundlePath "$result" test
done
