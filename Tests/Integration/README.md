# Isolated contract checks

For a fresh clone, use the [clone/CI runbook](../../docs/research/2026-10-28-clone-ci.md). Python 3.9+ and Git run the local tooling; Docker is required for backend schema exports and HTTP tests. Backend packages are never installed or imported on the host.

Download the exact current source from committed `Contracts/snapshot.json`, build from the clean Dockerfile, and run the boundary suite without any existing substrate image, `.reference`, or `.build`:

```sh
task_root="$(python3 -c 'import tempfile; print(tempfile.mkdtemp(prefix="fiestaboard-contracts-"))')"
python3 scripts/bootstrap-contracts.py --destination "$task_root/bootstrap" --build --test
```

The destination must not already exist. `bootstrap/bootstrap.json` records the source version/SHA and the produced immutable image ID. Omit `--build --test` to download source only. To test with an existing local immutable image, pass `--image sha256:... --test`; no preexisting image is silently selected. Build/test failure is an error, and completed source/image preparation remains available for diagnosis.

`../../scripts/contract-backend.py` is an explicitly local, standard-library utility. It imports no backend code. Every backend import/test runs in a fresh Docker container against `git archive` of an explicit full SHA, with source mounted read-only, network disabled, capabilities dropped, read-only root filesystem and temporary data. No ports, Docker socket, real credentials, user config or live service are mounted. Root `.env`, `data`, `config.json` and `auth.json` are omitted even if tracked. Paths are passed as argument arrays, including paths with spaces. Schema export and our HTTP tests never enter ASGI lifespan, so they do not start hardware workers.

Run from the iOS repository root. The current authoritative snapshot is 10.1.17; the original 10.0.0 snapshot remains separately archived under `Contracts/archive/10.0.0`. Replace `/path/to/FiestaBoard` with a Git repository containing the current pinned commit, and `sha256:...` with the clean-build receipt's image ID:

```sh
python3 -m unittest discover -s Tests/Contracts -v
contract_commit="$(python3 -c 'import json; print(json.load(open("Contracts/snapshot.json"))["source"]["commit"])')"
python3 scripts/contract-backend.py export --repo /path/to/FiestaBoard --commit "$contract_commit" --image sha256:... --root /tmp/new-contract-export
python3 scripts/contract-backend.py test --repo /path/to/FiestaBoard --commit "$contract_commit" --image sha256:...
python3 scripts/contract-backend.py test --upstream --repo /path/to/FiestaBoard --commit "$contract_commit" --image sha256:...
python3 scripts/check-contracts.py
python3 scripts/check-contracts.py --release-ready
```

Default checker mode validates artifact integrity and explicitly says NOT release ready. Release readiness requires all declared blockers resolved, every parity row verified, every inventory operation runtime verified, every operation contract supported, and a supported release with passed acceptance for auth, OAuth, conditional writes, operation fixtures, physical native verification, and proxy/ingress topology. Every acceptance category needs source-matching, repository-confined, hashed evidence. This checks evidence traceability and declared statuses; reviewers/CI must establish that evidence actually proves the acceptance criteria. Missing files and malformed references are errors. It needs only committed artifacts, not `.reference` or backend source.

## Build/rebuild

The authoritative generation image is recorded by content ID in `Contracts/snapshot.json`. A developer machine need not have that image. Build the clean Dockerfile and pass the resulting immutable ID explicitly to every export/test invocation. The seed lock and every tree digest must match the archived source. Generator metadata records all installed package versions and both seed/source lock identities. The exporter writes only to the supplied root above, so inspecting regenerated schemas does not overwrite committed evidence.

A complete build does not require the local bootstrap tag:

```sh
python3 scripts/contract-backend.py build --repo /path/to/FiestaBoard --commit "$contract_commit" --tag fiestaboard-ios-contract:clean
```

This builds `Dockerfile` from the official Python 3.14.9 slim image, official Debian build packages, exactly pinned PyPI dependencies in `dependencies.lock`, and pinned GitHub output repositories verified by the backend's seed builder. Build-time dependency downloads require network access. The base tag/OS packages are not byte-reproducible; pass the produced immutable image ID to every subsequent invocation using `--image sha256:...`, and preserve regenerated snapshot metadata. Python packages are locked to the tested substrate environment, which is recorded explicitly rather than represented as upstream's unbounded requirement resolution. This path is documented separately from the tested bootstrap optimization.

For the available dependency substrate, the optimized build verifies `fb-2354-test:latest` resolves to `sha256:77fc6a98ca7f16f15810fd0bd8b3b51e7a0ed81b90c38ce8ede492cd8a4caa62` before building `Dockerfile.bootstrap` and fetching/verifying the exact v10 seed into a fresh destination:

```sh
python3 scripts/contract-backend.py build --bootstrap --repo /path/to/FiestaBoard --commit "$contract_commit"
```

Build subprocesses select Docker's legacy builder to avoid buildx writing global client state. No global environment is changed. Build prints the produced content ID. `prepare --destination /new/path` can export source alone and refuses existing destinations.

## Coverage and limits

The historical 10 HTTP auth cases cover cookie login/logout and copied-cookie invalidation; enabled, disabled and undecided modes; session-management CSRF/Origin refusal with unchanged sessions; successful all-session revocation; TV token scope and revocation; and an authenticated non-auth domain 409. The runner discovers all committed `Tests/Integration/test_*.py`, including the separately documented current-source boundary fixtures. The domain-conflict case supplies a fake stored panel lookup and asserts real middleware preserves authentication. It does not exercise hardware or replace auth middleware/dependencies. Synthetic secrets remain in process memory and pytest output avoids response bodies that contain secrets.

`--upstream` runs exactly `tests/test_auth_routes.py`, `tests/test_auth_device_routes.py`, and `tests/test_auth_tv_permissions.py` (67 cases in this snapshot). Our own proof is collected separately without upstream conftest or its auth mode fixture. Upstream cases are supplementary evidence. This is not the entire upstream test suite, native app proof, HA upstream authentication, provider OAuth completion, conditional writes, exhaustive operation fixtures, or production/proxy topology validation. The upstream `FastAPI(root_path=...)` deprecation warning is retained and reported.
