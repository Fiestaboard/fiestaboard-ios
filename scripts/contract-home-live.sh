#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cx_action="${1:-check}"
[[ "$cx_action" == --record || "$cx_action" == check ]] || { echo 'Usage: scripts/contract-live.sh [--record]' >&2; exit 2; }
cx_repo="${CX_HUB_REPO:-/Volumes/ExtHD/workspace/fb-wt/cx-v11fix2}"
cx_commit="${CX_HUB_COMMIT:-f47da6e4e764fc2826f396210f013e45dc1a7fd8}"
[[ "$cx_commit" =~ ^[a-f0-9]{40}$ ]] || { echo 'Full immutable hub SHA required' >&2; exit 2; }
cx_out="${CX_HOME_OUT:-Tests/Fixtures/Home}"
cx_manifest="${CX_HOME_MANIFEST:-Tests/Fixtures/Home/requests.json}"
cx_image="cx-iosnext5-i7-contract-${cx_commit:0:12}-$(basename "$cx_manifest" .json)"
cx_base="python@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90"
cx_tmp=$(mktemp -d /private/tmp/cx-iosnext5-i7-contract.XXXXXX)
trap 'rm -rf "$cx_tmp"' EXIT
mkdir "$cx_tmp/hub"
git -C "$cx_repo" archive "$cx_commit" | tar -x -C "$cx_tmp/hub"
# Build a separate runtime from the recorded dependency lock; no shared app
# image or mutable data is a prerequisite. Capture the actual image identity.
cat > "$cx_tmp/Dockerfile" <<'EOF'
FROM python@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
COPY dependencies.txt /cx-dependencies.txt
RUN python -m pip install --no-cache-dir -r /cx-dependencies.txt
WORKDIR /app
COPY hub/ /app/
COPY recorder.py /cx-recorder.py
COPY requests.json /requests.json
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/app
ENTRYPOINT ["python", "/cx-recorder.py"]
EOF
cp scripts/record-home-fixtures.py "$cx_tmp/recorder.py"
cp "$cx_manifest" "$cx_tmp/requests.json"
cp Tests/Fixtures/Home/HostUndo/environment.txt "$cx_tmp/dependencies.txt"
# The public base needs no credential. Preserve the selected daemon endpoint,
# while avoiding unrelated Desktop credential helpers and their mutable logs.
cx_endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
mkdir "$cx_tmp/docker-config"
echo '{"auths":{}}' > "$cx_tmp/docker-config/config.json"
cx_docker=(docker --config "$cx_tmp/docker-config" --host "$cx_endpoint")
DOCKER_BUILDKIT=0 "${cx_docker[@]}" build -t "$cx_image" "$cx_tmp"
cx_image_id=$("${cx_docker[@]}" image inspect "$cx_image" --format '{{.Id}}')
cx_base_digest=$("${cx_docker[@]}" image inspect "$cx_base" --format '{{json .RepoDigests}}')
mkdir "$cx_tmp/fixtures"
"${cx_docker[@]}" run --rm --name "cx-iosnext5-i7-contract-${cx_commit:0:12}-$$" --network none --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,size=128m \
  --env "CX_HUB_COMMIT=$cx_commit" --env "CX_DOCKER_IMAGE=$cx_image_id" --env "CX_DOCKER_BASE=$cx_base_digest" \
  --mount "type=bind,src=$cx_tmp/fixtures,dst=/fixtures" "$cx_image"
if [[ "$cx_action" == --record ]]; then
  mkdir -p "$cx_out"
  cp "$cx_tmp"/fixtures/*.json "$cx_out/"
  cp "$cx_tmp/fixtures/environment.txt" "$cx_out/environment.txt"
else
  # New sessions/timestamps are expected; compare actual wire shapes/statuses,
  # then run the decoder contract against the newly recorded bytes.
  python3 - "$cx_tmp/fixtures" "$cx_out" <<'PY'
import json,sys
from pathlib import Path
actual=json.loads((Path(sys.argv[1])/'SOURCE.json').read_text())
expected=json.loads((Path(sys.argv[2])/'SOURCE.json').read_text())
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
