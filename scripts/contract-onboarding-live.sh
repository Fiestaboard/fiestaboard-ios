#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${1:-}" == --record ]] || { echo 'Usage: scripts/contract-onboarding-live.sh --record' >&2; exit 2; }
cx_repo="${CX_HUB_REPO:-/Volumes/ExtHD/workspace/fb-wt/cx-v11fix2}"
cx_commit="${CX_HUB_COMMIT:-f47da6e4e764fc2826f396210f013e45dc1a7fd8}"
[[ "$cx_commit" =~ ^[a-f0-9]{40}$ ]] || { echo 'Full immutable hub SHA required' >&2; exit 2; }
cx_base='python@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90'
cx_image="cx-iosnext5-i9-onboarding-${cx_commit:0:12}"
cx_tmp=$(mktemp -d /private/tmp/cx-iosnext5-i9-contract.XXXXXX)
# Preserve this owned build/recording evidence even on failure; never clean another session's data.
mkdir "$cx_tmp/hub" "$cx_tmp/fixtures" "$cx_tmp/docker-config"
git -C "$cx_repo" archive "$cx_commit" | tar -x -C "$cx_tmp/hub"
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
cp scripts/record-onboarding-fixtures.py "$cx_tmp/recorder.py"
cp Tests/Fixtures/Onboarding/requests.json "$cx_tmp/requests.json"
cp Tests/Fixtures/Home/HostUndo/environment.txt "$cx_tmp/dependencies.txt"
cx_endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
echo '{"auths":{}}' > "$cx_tmp/docker-config/config.json"
cx_docker=(docker --config "$cx_tmp/docker-config" --host "$cx_endpoint")
cx_bounded() {
  python3 - "$@" <<'PYBOUND'
import subprocess, sys
try:
    result = subprocess.run(sys.argv[2:], timeout=int(sys.argv[1]))
except subprocess.TimeoutExpired:
    print('Owned Docker CLI deadline exceeded; inspect this task before any further attempt.', file=sys.stderr)
    raise SystemExit(124)
raise SystemExit(result.returncode)
PYBOUND
}
cx_bounded 120 env DOCKER_BUILDKIT=0 "${cx_docker[@]}" build -t "$cx_image" "$cx_tmp"
cx_image_id=$(cx_bounded 15 "${cx_docker[@]}" image inspect "$cx_image" --format '{{.Id}}')
cx_base_digests=$(cx_bounded 15 "${cx_docker[@]}" image inspect "$cx_base" --format '{{json .RepoDigests}}')
cx_bounded 300 "${cx_docker[@]}" run --rm --cpus 1 --label com.fiestaboard.task=cx-iosnext5-i9 --name "cx-iosnext5-i9-onboarding-${cx_commit:0:12}-$$" --network none --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,size=128m \
  --env "CX_HUB_COMMIT=$cx_commit" --env "CX_DOCKER_IMAGE=$cx_image_id" --env "CX_DOCKER_BASE=$cx_base_digests" \
  --mount "type=bind,src=$cx_tmp/fixtures,dst=/fixtures" "$cx_image"
cp "$cx_tmp"/fixtures/*.json Tests/Fixtures/Onboarding/
cp "$cx_tmp/fixtures/environment.txt" Tests/Fixtures/Onboarding/environment.txt
echo "Original owned build and recording evidence: $cx_tmp"
