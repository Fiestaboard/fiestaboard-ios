# Current contract refresh — October 28, 2026

Reference: FiestaBoard **10.1.17**, exact upstream commit `b5eac069dce10945eac61e1fdadf6ee4a903ba08`. This is a source and isolated runtime candidate, not identification of the installed test server or approval of an adapter/version gate.

## Inventory and provenance

The original 10.0.0 six-file contract bundle is preserved byte-for-byte in `Contracts/archive/10.0.0/`, including its original source `2ced809c8fe20d4ac6e5dc6603d691c8cb4e475a`, 81 parity rows and 198 operations. The scoped 10.1.7 collection corpus remains at `Fixtures/contracts/collections-v1.json` with its original source attribution. Neither history was relabeled.

The current bundle has **84 planned parity rows and 199 candidate/schema-only operations**. The additions are the public `/discover` identity probe and explicit color-rule, JSON mapper and schema-widget workflows. Every original workflow/operation ID is retained. Row/operation mappings are reciprocal. Current references carry the exact source commit, whole-file SHA-256 and in-range current line. Operations additionally bind the current backend route definitions; old backend line citations in notes were removed. No operation, row or release was promoted to supported/verified.

`Contracts/current-source-ledger.json` enumerates all 26 real `web/app/routes/*.tsx` modules, the router configuration and 975 bounded source sites for API helpers, direct fetch, SSE, upload/download, browser navigation and OAuth. It includes non-barrel route modules. These sites are audit evidence, not 975 distinct operations. The 36 public and 278 internal schema entries are unchanged in count from the original export. Internal includes public operations; 115 schema/surface entries are outside the authored inventory, of which 22 represent an endpoint mapped on the other surface and 93 are distinct unadopted endpoints. They remain explicitly listed; schema presence does not imply useful native adoption or support.

The ledger records six changed public operation declarations and 18 changed internal declarations, plus the complete changed model list. Important model changes include page/document extension preservation, collection/schedule edit generations, default-page revisions, canvas/document shape distinctions, nullable polling fields and schedule response metadata. `Contracts/current-capabilities.json` supplies each mapped operation's exact method, path, surface, schema hash, request/response declarations, auth, scope, effects and replay policy. It is a candidate input list; version comparison alone authorizes nothing.

The Docker export verifies each output seed tree and its lock against the pinned source. Current schemas were exported on clean image `sha256:79ecc5613dec30c8d46ce5533083e1093a85b2295556e7de3111bf63032ef530`, built separately by W0-B from its clean source path. `snapshot.json` records the actual Python/dependency/image environment, a digest of the source manifest and hashes of current companion artifacts. Backend imports run only in Docker, network disabled, read-only source, temporary data and no ASGI lifespan. A fresh empty output directory export was also executed and its two schemas matched the committed files byte-for-byte.

## Bootstrap contract

Paths below are backend paths; a deployment's `/api` prefix is a transport/topology concern, not part of these DTOs.

| Operation | Contract |
| --- | --- |
| `GET /health` | Public: `{status: string, service_running: boolean, version: string}`. |
| `GET /discover` | Public, `Cache-Control: no-store`: `{product: string, version: string, id: string, name: string}`. Product is `FiestaBoard`; ID is stable per install and can be empty if storage fails. Name is empty unless auth is disabled. A configured nonempty name is tested in all three auth modes. |
| `GET /auth/status` | Public/no-store: `enabled`, `setup_required`, `authenticated`, `username: string|null`, `mode: enabled|disabled|undecided`, `first_run`, `session_management_supported`, `auth_kind: browser|tv|null`, `tv_sign_in: {supported, enabled, protocol_version: 1}`. |
| `POST /auth/setup` | `{username, password}`; username 1–64 characters, password 8–1024. Success 201 `{status: "ok", username}` and persistent session cookie. Duplicate setup 409. |
| `POST /auth/login` | `{username, password, remember_me?}`; remember defaults false. Success 200 `{status: "ok", username}`. Wrong credentials 401; no user yet 409; throttle 429 with `Retry-After: 60`. Validation 422 carries a `detail` array. |
| `POST /auth/logout` | Revokes session and clears cookie; 200 `{status: "ok", username: null}`. |
| `GET /version` | Protected: `{package_version, build_version, running_version, is_dev, hardware_model: string|null}`. Display `running_version`; it does not establish exact source identity. Hardware-model detection is deliberately substituted with null in the isolated fixture. |

The exact cookie name is **`fiestaboard_session`**, HttpOnly, Path `/`, SameSite `lax`; Secure on HTTPS (including the backend's forwarded-proto handling). Session login omits Max-Age; remembered login/setup currently has Max-Age 2592000 seconds. Cookie tokens are never committed. Logout has Max-Age 0. The corpus tests all these attributes, including Secure. Native clients must preserve the server-issued cookie, not synthesize or replay credentials.

Authenticated=false status is a successful status DTO, not an HTTP error. A protected call before setup has 409 `{detail: "Setup required", setup_required: true, first_run: ...}`. An ordinary authenticated business 409 must not be classified as logout. A protected unauthenticated call has 401 `{detail: "Not authenticated"}`. TV bearer scope remains panel-only; existing middleware boundary tests prove it cannot serve as a general native admin credential.

## Behavior corpus and limits

`Fixtures/contracts/current/bootstrap-control.json` contains **57** generated/replayed cases: auth modes, name privacy/stable discovery identity, version, setup and validation, wrong credentials and lockout, session/persistent/Secure cookie metadata, board list/detail/not-found, sparse/null PATCH, paused restore, UI-only restore, paused preview without a temporary override, no-runtime message refusal, conflicting message inputs, document-extension preservation, page/collection/schedule/default original-revision refusal and flagship/Note-array/panel geometry plus filled 71 preview.

The current page update response is `{page, incompatible_references}`, not a bare Page. Sparse update preserves the opaque author extension; explicit `canvases: null` clears it. Original generation tokens cause stale update/delete 412; schedule omission retains `end_time` and explicit null clears it. Default revisions have `schedule-default-revision-v1`. Board PATCH has no revision precondition in this source; candidate inventory does not grant it concurrent-write safety. A paused/UI-only message or restore acknowledgment has `sent: false`; no physical output was observed.

Capture/replay substitutes the lazy runtime getter with None to prevent implicit display-service initialization, and supplies a service/client only for the paused preview case. Hardware writes and provider calls are not executed. Dynamic IDs/revisions are consistently aliased, timestamps normalized, cookie values omitted and fixture passwords redacted. Real middleware, DTO validation, handlers and temporary content stores remain active. The source suite separately exercises atomic concurrent generations, reload/recreation, extension validation and breaker behavior. Its upstream test harness is not authentication proof; that proof comes from the separately run no-override middleware tests.

Filled code 71 is source-bound distinctly from black 70 in `board-characters-to-template.ts` and TipTap's constants; backend preview yields `{71}`. Cache lookup now precedes the plugin breaker, so a late cached answer clears quarantine for the same plugin/geometry. The two late-answer source tests passed. Color-rule ordering/conditions/fallbacks and generated field-color variables, JSON path mapper aliases and request/row key remapping, `ui:visible_when`/sections, secret/textarea/timezone/page/enum/remote-options controls and core mode-card/device-picker/tile-grid widgets are explicitly enumerated. Their native UI equivalence remains planned.

Rich editing has two source-backed families. Split-flap retains the app TipTap editor. LED uses `@fiestaboard/ui` **8.14.2** `TemplateEditor`, pinned by the current package lock, with color spans (`{{red:HOT}}`), block spans (`{{black/white:OPEN}}`), icons (`{{icon:sun}}`), mixed case and unsupported-cell markings. Separate rich/plain, IME, selection, undo, preview, save/conflict/recovery and resize acceptance is required for both. The source bindings and backend corpus do not prove those native interactions; raw-only LED is not equivalent.

## Fresh verification

- `python3 -m unittest discover -s Tests/Contracts`: **41 passed** after new negative tests were observed failing first. Includes stale/wrong-source references and manifest/artifact hashes, required backend source, reciprocal mappings, unsupported status promotions, capability schema drift and fresh-output-root mounting.
- `python3 scripts/check-contracts.py`: passed. `--release-ready`: refused as expected; candidate declarations/blockers remain.
- `python3 scripts/contract-backend.py test --repo <upstream-git> --commit b5eac069dce10945eac61e1fdadf6ee4a903ba08 --image sha256:79ecc5613dec30c8d46ce5533083e1093a85b2295556e7de3111bf63032ef530`: **11 passed**, comprising ten existing real-middleware tests plus a fresh-process 57-case current replay. One existing FastAPI root_path deprecation warning.
- Isolated current source selection: **103 passed**, 25 upstream deprecation warnings (FastAPI root_path and datetime.utcnow). Files: `tests/test_page_revisions.py`, `test_page_document_preservation.py`, `test_content_revisions.py`, `test_plugin_fetch_breaker.py`, `test_pages_custom_grid_display.py`, `test_v1_preview_safety.py`.
- Fresh empty output-root Docker export: succeeded, both normalized schemas byte-identical to current committed schema artifacts.

To reproduce the source selection using the same fencing, run this local stdlib orchestration (only the container imports backend code):

```python
import importlib.util, json, subprocess, tempfile
from pathlib import Path
spec = importlib.util.spec_from_file_location("runner", "scripts/contract-backend.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
snapshot = json.loads(Path("Contracts/snapshot.json").read_text())
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp) / "source"
    r.prepare(Path("/path/to/upstream-git"), snapshot["source"]["commit"], source)
    (source / "data").mkdir()
    tests = ["test_page_revisions.py", "test_page_document_preservation.py",
             "test_content_revisions.py", "test_plugin_fetch_breaker.py",
             "test_pages_custom_grid_display.py", "test_v1_preview_safety.py"]
    command = ["-m", "pytest", "-p", "no:cacheprovider", "--tb=short", "-q"]
    command += ["tests/" + name for name in tests]
    subprocess.run(r.container(source, snapshot["generator"]["image"], [], command), check=True)
```

Whole-backend tests, frontend/browser widget/editor interaction tests, live LAN/server identity, provider OAuth, physical output and native rich editor acceptance were not run by W0-A. They remain explicit program work. Adapter scope requires independent Astra acceptance before any version gate or support status changes.
