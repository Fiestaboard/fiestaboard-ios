# Current-source board-control contract evidence

This 72-case corpus captures FiestaBoard 10.1.17, immutable source `b5eac069dce10945eac61e1fdadf6ee4a903ba08`, through real authenticated ASGI middleware, handlers, temporary settings/page/schedule stores, message executors and `DisplayService` restore passes. It supplements the bootstrap corpus, which only previewed messages. It is candidate evidence for this exact source; it changes no compatibility or release status.

Every backend import and request runs in Docker image `sha256:79ecc5613dec30c8d46ce5533083e1093a85b2295556e7de3111bf63032ef530`, with network disabled, read-only archived source, temporary data, no ASGI lifespan and no service initialization. The only synthetic execution boundaries are an in-process output client, the adaptive output-read refresh request, provider-context fetching, and the fixed clock. The output stub returns actual source `WriteResult` objects or deliberately malformed/timeout results. It records the projected frame and rich cells. Real hardware clients are never constructed. A fixture `sent:true` records simulated acceptance at that boundary; no physical output was observed.

The fixture is [board-control.json](../../Fixtures/contracts/current/board-control.json). Each case records method, path, query when present, JSON body when present, content type and session-cookie presence/name metadata, response status/body and `Retry-After` when returned, plus final output-boundary calls. Cookie/password/token values are absent. Generated IDs, revisions and timestamps use the bootstrap alias convention. Generation and replay use fresh interpreters to prevent singleton-store leakage.

| Operation | Request | Receipt and interpretation |
| --- | --- | --- |
| List/detail | `GET /v1/boards`, `GET /v1/boards/{board}` | Concrete ID, output, device model, charset, geometry and controls. Detail includes current/expected characters, page selection and source. Cached characters alone are not device observation. |
| Send | `POST /v1/boards/{board}/message` | Exactly one of `text`, `lines`, `characters`, `page_id`, `fill`, `plugin_id`, `template`. Receipt: `sent`, concrete `board_id`, `characters`, `text`, nullable `expires_at`/`reason`, `silenced`, `held`. `force` defaults false; no automatic force or replay. |
| Restore | `POST /v1/boards/{board}/restore`, no body | `board_id`, nullable `page_id`, `sent`, nullable `reason`, `device_observed:false`. Selection stays selected. A successful restore confirms only the send boundary accepted it. |
| Select page | `PUT /v1/boards/{board}/active-page`, `{page_id:string|null,override_silence?:bool}` | `board_id`, `page_id`, `sent`, `silenced`, nullable `reason`/`error`, `warnings`. Selection is persisted even when the immediate send fails. `null` explicitly unpins. |
| Scalar controls | `PATCH /v1/boards/{board}`, sparse `paused`, `schedule_enabled`, `auto_restore`, `name` | Returns board detail. Omitted fields and null scalar values preserve other controls. There is no revision protocol. |
| Read default | `GET /schedules/default-page?board_id=CONCRETE_ID` | `revision`, `edit_protocol:"schedule-default-revision-v1"`, nullable `default_page_id`. Board scope is the query; receipt has no board ID. |
| Conditional default write | `PUT /schedules/default-page`, `{page_id:string|null,board_id:CONCRETE_ID,expected_revision:ORIGINAL}` | Same default receipt. Board scope is the body. Preserve the original revision; stale writes return 412. `page_id:null` explicitly clears. |

Optional send fields are `force`, `override_silence`, `if_paused` (`reject`/`preview`), duration/revert fields and transition overrides. The corpus proves primary timed text acknowledgement, no timed override after a throttled refusal, and 400 refusals for secondary timed messages and raw-grid/fill durations. Duration is supported only on the primary board for text-like content. Rendering provider-backed plugin content and real transition/device timing remain outside this corpus.

| Observed branch | HTTP/result | Client consequence |
| --- | --- | --- |
| Boundary accepted | 200, `sent:true` | Server acknowledgement only; never promote to physical observation. |
| Unchanged | 200, `sent:false`, reason | Already equal according to the supplied driver outcome. No force or automatic resend. |
| UI-only | 200, `sent:false`, reason; no driver call | Configuration accepted the request without output. |
| Paused preview | 200, `sent:false`, reason; no driver call/override | Preview only. |
| Pause/silence refusal | 409 detail | Policy refusal; preserve user intent without automatic mutation replay. |
| Held during silence | 202, `sent:false,silenced:true,held:true` | Intent is held for later. Queue insertion and explicit override clearing are asserted; later physical delivery is unexecuted. |
| Throttled | 429 detail, `Retry-After:7` | This output attempt did not land; the test proves the refusal does not arm a timed override. |
| Superseded | 409 detail | Newer work superseded this write before delivery. |
| Partial array write | 502 structured `detail` | `partial:true`, message, `failed_regions:[{row,col,rows,cols}]`; retain partial failure distinctly. |
| Driver failure/timeout/malformed outcome | 500 detail | Captures real server settlement/coercion. These are deterministic server responses, not a model for an unknown network outcome at the native client. |
| Missing reference/board | 404 detail | No force or replacement resource is invented. |
| Geometry/invalid request | 400 or framework 422 | Keep validation errors distinct from send failures. |

Page selection has a different taxonomy from message send: a failed immediate send returns 200 with `sent:false,error:string`, and selection remains stored. A paused selection returns 200 with `sent:false,silenced:false,reason:null,error:null` because the v1 response omits the internal paused flag. Inspect board state before choosing wording. A silenced selection reports `silenced:true` and a reason. Restore returns 200 with `sent:false` for UI-only and schedule gaps/no-output; paused/silenced restore returns 409 and failed restore returns 500.

The targets are synthetic `contract-board` (Vestaboard Flagship, 6×22, `vestaboard_v1`), `contract-led` (FiestaPanel LED, 8×16, `led_5x7`) and `contract-array` (Note array, 3×30, `vestaboard_v2`). LED projection carries rich cells and split-flap projection does not. Secondary selection, restore, pause/resume and conditional default writes are captured with concrete target IDs. Assertions show the primary selection/pause/default value is preserved. Default revisions are conservative across boards: they combine schedule-default storage generation with settings generation, so changing the secondary default invalidates the original primary token even when its value is unchanged. The old primary token then returns 412.

Board PATCH also accepts `default_page_id`, but it is unconditioned and sequential. The corpus sends `{paused:true,default_page_id:"missing"}` and receives 404 after pause has already persisted. Do not replace conditional default PUT with PATCH, combine defaults and other fields as one atomic transaction, or claim universal conflict protection.

Source line references below are relative to the frozen source commit. Exact SHA-256 digests for all inspected execution files are embedded in the fixture and checked against `Contracts/snapshot.json`.

| Source | Lines | SHA-256 |
| --- | --- | --- |
| `src/v1/routes_boards.py` | list 113; detail 138; PATCH 208; settlement 356; message 427; restore 683; active-page 758 | `12a893845973109a062376ad33fbae7d04f377c6b44c038a9a3efdeb1e058baf` |
| `src/v1/models.py` | message receipt 298; selection 377; restore 404 | `1eef333e1518ca37ed6a6d54094fe11cc76e08b6d56b960c1e1620e1cfbd8b52` |
| `src/ops/executors.py` | target guards 772; settlement 915; text send 1012 | `3fb5d11e2a6457499ac3f8db216dad6bf504f7ddea9c47009afa540356aff463` |
| `src/displays/messages.py` | driver render boundary 24 | `91ff3733a87338a2c1f64cb84b802b0396f26068adbadc30a97d83a551cec1b6` |
| `src/settings/routes.py` | persisted selection/immediate send 617 | `3f32bc80004135ab4ef69d6ec2aacdfbd24c8ad93bb5d57ac614586910442bd6` |
| `src/schedules/routes.py` | default GET 258; conditional PUT 269 | `5acdddbb4ce2bdf3c155d1588f1544b328724ecd007be1915fa434d90f97b237` |
| `src/schedules/service.py` | composed generation 365; state read 381; conditional setter 386 | `492c4def0afac8d9099c54e953a34224cac064fbdb741cec850df3c68d0a6e01` |
| `src/main.py` | restore status 644; invalidation 1152; board pass 2031 | `2df701f3a80387d1e9a643bb57349c6410b0853e73231e1905d3c241fc58b1c9` |
| `src/send_outcome.py` | `WriteResult` 43 | `26109f1cdf238352f3d0c877a329f7a056329fd4f3d6479c026c8820e5ce0a0a` |
| `src/board_guards.py` | real silence/held verdict 277 | `9abed066fbf18d7773088a0349401041a94f904df654b36eccfa13d8676b5a38` |

The new companion is required whenever present, including when stale. Export rejects a source mismatch rather than dropping it; checker rejects omitted registration, wrong exact bytes, missing file, wrong registration source, rehashed wrong embedded source and rehashed wrong source-file digests. Existing companion and embedded capability-schema checks remain unchanged. Empty-root export remains valid. Candidate statuses and the original 10.0.0/10.1.7/bootstrap artifacts remain unchanged.

Reproduce the focused fenced replay with:

```sh
python3 scripts/contract-backend.py test \
  --repo /Users/jeffre/workspace/fiestaboard-ios-api \
  --commit b5eac069dce10945eac61e1fdadf6ee4a903ba08 \
  --image sha256:79ecc5613dec30c8d46ce5533083e1093a85b2295556e7de3111bf63032ef530 \
  --current-controls
```

The normal fenced `test` action also includes the new replay and existing middleware/bootstrap regressions. One test replays the source in a fresh process; another alters only a restore receipt's `device_observed` field and requires replay to fail. Local Contracts/Tooling tests use only JSON and stdlib utilities and never import backend code. Native malformed HTTP receipts, unknown outcomes, ambiguous mutation recovery, physical devices, provider-backed output and deployment compatibility remain separate acceptance work.
