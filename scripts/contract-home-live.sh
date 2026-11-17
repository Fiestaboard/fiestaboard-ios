#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cx_action="${1:-check}"
[[ "$cx_action" == --record || "$cx_action" == check ]] || { echo 'Usage: scripts/contract-live.sh [--record]' >&2; exit 2; }
cx_repo="${CX_HUB_REPO:-/Volumes/ExtHD/workspace/fb-wt/cx-v11fix2}"
cx_commit="${CX_HUB_COMMIT:-f47da6e4e764fc2826f396210f013e45dc1a7fd8}"
[[ "$cx_commit" =~ ^[a-f0-9]{40}$ ]] || { echo 'Full immutable hub SHA required' >&2; exit 2; }
cx_tmp=$(mktemp -d /private/tmp/cx-iosnext5-i7-contract.XXXXXX)
trap 'rm -rf "$cx_tmp"' EXIT
mkdir "$cx_tmp/hub"
git -C "$cx_repo" archive "$cx_commit" | tar -x -C "$cx_tmp/hub"
# Use a locally installed dependency substrate; replace every source byte with
# the immutable hub archive. Never read another container's mutable data.
cat > "$cx_tmp/Dockerfile" <<'EOF'
FROM fb21:local
WORKDIR /
RUN find /app -mindepth 1 -maxdepth 1 ! -name data -exec rm -rf {} + && find /app/data -mindepth 1 -delete
WORKDIR /app
COPY hub/ /app/
COPY recorder.py /cx-recorder.py
COPY requests.json /requests.json
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/app
ENTRYPOINT ["python", "/cx-recorder.py"]
EOF
cp scripts/record-home-fixtures.py "$cx_tmp/recorder.py"
cp Tests/Fixtures/Home/requests.json "$cx_tmp/requests.json"
DOCKER_BUILDKIT=0 docker build -t cx-iosnext5-i7-contract "$cx_tmp"
mkdir "$cx_tmp/fixtures"
docker run --rm --name "cx-iosnext5-i7-contract-$$" --network none --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,size=128m --env "CX_HUB_COMMIT=$cx_commit" --mount "type=bind,src=$cx_tmp/fixtures,dst=/fixtures" cx-iosnext5-i7-contract
if [[ "$cx_action" == --record ]]; then
  cp "$cx_tmp"/fixtures/*.json Tests/Fixtures/Home/
else
  # New sessions/timestamps are expected; compare actual wire shapes/statuses,
  # then run the decoder contract against the newly recorded bytes.
  python3 - "$cx_tmp/fixtures" <<'PY'
import json,sys
from pathlib import Path
actual=json.loads((Path(sys.argv[1])/'SOURCE.json').read_text())
expected=json.loads(Path('Tests/Fixtures/Home/SOURCE.json').read_text())
assert actual['hubCommit']==expected['hubCommit'], 'hub commit drift'
assert [(r['file'],r['status']) for r in actual['responses']]==[(r['file'],r['status']) for r in expected['responses']]
for response in actual['responses']:
    assert isinstance(json.loads((Path(sys.argv[1])/response['file']).read_text()),dict)
print('Live mobile contract statuses and JSON boundaries agree')
PY
  cx_build_root="$HOME/Library/Developer/FiestaBoard/ios"
  cx_swift_args=()
  [[ -z "${SWIFTPM_DISABLE_SANDBOX:-}" ]] || cx_swift_args+=(--disable-sandbox)
  CX_HOME_FIXTURES="$cx_tmp/fixtures" swift test "${cx_swift_args[@]}" --package-path Packages/FiestaBoardKit \
    --scratch-path "$cx_build_root/swiftpm-build/cx-iosnext5-i7/FiestaBoardKit" \
    --cache-path "$cx_build_root/swiftpm-cache" --config-path "$cx_build_root/swiftpm-config" --security-path "$cx_build_root/swiftpm-security" \
    --filter HomeContractTests/testRecordedHomeRepliesDecode
fi
