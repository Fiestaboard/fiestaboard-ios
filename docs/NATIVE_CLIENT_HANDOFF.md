# Native client pause / model-switch handoff

**Historical pause checkpoint — resumed by the user later on October 28, 2026. See TASKS.md for current status.**

Original pause record: Do not resume implementation until the user resumes with the new model. The running UI implementer was interrupted; no new work was dispatched after the pause. Do not discard or reset the uncommitted fixes.

## Progress chart

Green means implementation accepted by Astra for its bounded scope, not full runtime/release acceptance.

| Workstream | State | Remaining gate |
| --- | --- | --- |
| Current source/API inventory | ✅ Reviewed | All workflows still need native release acceptance |
| Fresh clone, build scripts, live/demo schemes, CI definition | ✅ Reviewed implementation | Hosted CI and actual Simulator UI runtime not executed |
| Public bootstrap, auth choice/setup/login, safe errors | ✅ Reviewed | Native device walkthrough |
| Verified Bonjour discovery + metadata-only catalog | ✅ Reviewed | Device permission/LAN discovery acceptance |
| Explicit secure remembered sessions/Keychain adapter | ✅ Reviewed | Actual device Keychain/lifecycle acceptance |
| Native connection UI + Store lifecycle | ⏸️ Review fixes implemented, uncommitted | Final tests/build and scoped Astra recheck |
| Current 10.1.17 board controls | 🟡 72-case source fixture committed | Astra fixture review, native adapter/capability adoption |
| Rich split-flap AND LED editor | ⬜ Required; source matrix saved | Implementation, round-trip/render/IME/undo/save/device proof |
| Remaining web/native parity and release | ⬜ Queued | Follow all waves/checklist; no reduced-scope release |

The current inventory has **84 workflows and 199 operations**. The master human checklist has **364 checks**. Do not calculate a whole-product completion percentage from the infrastructure work above. No supported/release-ready app/server pairing is declared.

## Exact workspace state

- Main user/Xcode checkout: `/Users/jeffre/workspace/fiestaboard-ios`, branch `main`, HEAD **`c57774f`**. It still contains the older reviewed Collections draft, not this wave's new connection code.
- Main's only tracked modification is the user's `FiestaBoard.xcodeproj/project.pbxproj` signing/project overlay. Preserve it exactly. SHA256 observed at pause: **`99ec26d71b98e10e01518ef89cb75fef074b8ac5ae72f00cab822540f473cb08`**.
- Active isolated implementation: `/Users/jeffre/workspace/fiestaboard-ios/.worktrees/foundation`, branch **`codex/ios-foundation`**, committed HEAD **`e621b2e`** before this handoff document.
- Existing ignored plan workspace: `.superpowers/sdd/2026-10-28-native-parity-completion/`. It contains `progress.md`, `task-N-brief.md`, `task-N-report.md`, review packages, review verdicts and logs. **Do not git-clean it or re-dispatch completed tasks.**
- Source pin: FiestaBoard **10.1.17**, `b5eac069dce10945eac61e1fdadf6ee4a903ba08`. Git source at `/Users/jeffre/workspace/fiestaboard-ios-api`; clean archive at main checkout `.reference/FiestaBoard-v10.1.17`.
- Backend PR #2373 is already merged. Original dirty backend checkout and unrelated Home Assistant checkout files were left untouched. Use `gh`, not the GitHub connector.
- No native remote/push/PR was established during this wave. No production deployment, physical send or App Store action occurred.

## Uncommitted state to preserve and finish first

Five production/test files contain **Task 6 fix round 1**:

1. `App/FiestaBoardApp.swift`
2. `Packages/FiestaBoardAppState/Sources/FiestaBoardAppState/BoardStore.swift`
3. `Packages/FiestaBoardAppState/Sources/FiestaBoardAppState/ConnectionModel.swift`
4. `Packages/FiestaBoardAppState/Tests/FiestaBoardAppStateTests/BoardStoreTests.swift`
5. `Packages/FiestaBoardAppState/Tests/FiestaBoardAppStateTests/ConnectionModelTests.swift`

Root-owned `TASKS.md` and `docs/native-parity-checklist.md` also have uncommitted current-status/84-row expansion edits. They are not user signing changes and must not be lost or accidentally included in another worker's commit.

Task 6's initial commit `4b32357` was reviewed by Astra with three Important findings. The implementer `/root/native_connection_ui` was interrupted while completing the fix report/final verification:

- Preferred-board restoration used `selectBoard → refresh`, implicitly clearing an unknown-command barrier. The current fix adds preferred board selection to the **initial** Store load, avoiding implicit recovery readback.
- Retrying a failed required shell load disconnected the same authenticated service and lost its cookie. The current fix uses cookie-preserving reconnect only for a still-retained handed-off service.
- Each DraftScene created a separate actor writing the same catalog file. The current fix defines App-owned `ConnectionPersistence` in the existing Model file and passes the same catalog actor into all scenes, leaving Model/Store/session scene-local.

The worker reported the first two fixes' focused regressions green and a catalog-sharing test covering same actor/40 inserts/concurrent changes. At pause, **`/private/tmp/task6-round1-appstate.log` ends with 73 tests and zero failures**. Do not assume that closes the task: the fixes are uncommitted, its report still needs the round-1 update, and Astra has not rechecked this diff. Root `git diff --check` was clean at pause. No final post-fix iOS build ran.

Finish these exact fixes, inspect the complete log/source correspondence, run only justified remaining validation, append the fix report, commit only the owned paths, and request a scoped recheck against `4b32357`. Generate review packages from **all actual changed paths**, not a handpicked list that can omit a new test file.

## Completed implementation and review evidence

| Task | Commits | Verdict / evidence |
| --- | --- | --- |
| 1 / W0-A current contracts | `54016e9`, `c527bfd` | Astra approved. Wrong-source companion omission and embedded-schema drift fixed. Original six-file10.0.0 archive byte-preserved; current84 rows/199 ops remain candidates/planned. |
| 2 / W0-B clone/CI | `713946b`, plus Task1 runner fix | Astra approved implementation after fresh-output-root export fix. Local native clone proof passed; hosted/UI runtime still open. |
| 3 / W1-A bootstrap | `1fcbb06`, `bbea377` | Astra approved after setup/preference generation + late logout cookie regressions. Kit82 at that point; no version gates broadened. |
| 4 / W1-B discovery/catalog | `ff74417`, `84863ce` | Astra approved after actual callback ordering and canceled-task capacity fixes. Reviewer probes confirm configured concurrency1 and removal order. |
| 5 / W1-C sessions | `cdd3ee7`, `8b857de` | Astra approved after final restore ownership-check and stale cleanup generation fixes. Persistence22/Kit120/AppState67 logs inspected. |
| 6 / W1-D Model/UI | `4b32357` plus uncommitted fixes | Initial AppState69/Kit120/Editor50/Documents25 green. Three Important findings under round1 correction as above. |
| 7-A / W1-E control fixtures | `e621b2e` | **Not reviewed yet.** 72-case fixture; Contracts56/Tooling15/fenced Integration13 passed, candidate-only. |

Root project registration commits: `b94e849`, `eb2654a`, `b4008b0`. New source files and `_http._tcp` Bonjour declaration are registered in the isolated project. Do not regenerate main's project over the user's signing edits.

Latest completed root unsigned device build before the final Task6 tweaks/fixes: `.superpowers/sdd/2026-10-28-native-parity-completion/connection-ui-device.log` contains BUILD SUCCEEDED. Later Task6 edits require final normal + Demo device builds and UI-test compilation. Device installation, native UI runtime, VoiceOver, geometry and actual device Keychain are **not verified**.

Fresh native clone proof at committed `54016e9` used a new temp directory without `.reference`/`.build`: tooling15, contracts41, project/integrity, all186 original Swift package tests, public-source Docker bootstrap (11 boundary cases including57 current corpus), and unsigned device build passed. Path/logs are recorded in the plan workspace's `clone-proof-path` and `clone-proof/`. This proves that exact checkpoint, not every later feature.

## Live test instance: checked directly, do not ask the user to look it up

`http://fiestapi.local:4420` is reachable through the **Safari MCP tools**, even though exec Python/curl/network routing cannot reach it in this managed environment. CUA native pipe, Simulator services and CoreDevice CLI were unavailable. Discover relevant tools through `ALL_TOOLS`; successful tools are `mcp__mcp_safari__tabs_create`, `navigate`, `read_page`, `javascript_tool`.

Root verified through Safari:

- Public discover returns FiestaBoard10.1.17.
- Supplied test account login returned200; authenticated `/api/version` reports package/build/running10.1.17 and `is_dev:false`.
- `/api/health` is ok, `service_running:true`.
- `/api/v1/boards` returned200, four targets: flagship6×22 `vestaboard_v1`; panel9×22 `vestaboard_v2`; LED panels8×10 and12×29 using `led_5x7`. Personal names/IDs are intentionally not copied here.
- Temporary browser session logout returned200. A later optional detailed-board-shape check exceeded the extension's30-second wait; no result was claimed. Follow-up auth status verified `authenticated:false`. No temporary signed-in browser session is left by that check.
- Owned Safari tab **15710** is currently on `/api/auth/status`.

Credentials are in the existing conversation only, **not this file/repository**. Do not ask again merely because CLI access fails; Safari can read the instance. Do not confuse browser API proof with native iPhone/Keychain proof. No physical sends, driver writes, provider authorization, restart or server configuration changes were made.

## Next implementation: current-version native controls

Task7-A report/brief at the plan workspace are ready for Astra review. `Fixtures/contracts/current/board-control.json` has72 fenced source-handler cases, SHA256 `0d2400cf846e771f92bffa4fdf46f36e32f11a5e929f14e4ecbed8e1cc3dca50`. It uses source b5eac..., final driver/provider boundaries stubbed and real middleware/runtime/settings with temporary data. No native adapter has adopted it yet.

Important source facts for Task7-B:

- Board commands still retain exact non-development **10.0.0** gating. The user's actual10.1.17 needs its own tested candidate policy; do not merely change a version string or allow >=versions.
- Message URI captures concrete board; body accepts exactly one text/lines/characters/page/fill/plugin/template input. Source receipt is sent/board_id/characters/text/expires_at/reason/silenced/held. Held202 is not a physical send.
- Restore returns board_id/page_id/sent/reason/device_observed:false; accepted send is not observed output.
- Public v1 active-page target is `/boards/{board}/active-page`, not an ignored body board_id. Selection can persist with sent:false/error. Its DTO drops internal paused; inspect current board state, don't infer generic success.
- Defaults GET `/schedules/default-page?board_id=...`; PUT body includes page_id (nullable), board_id, original expected_revision. Response includes revision/protocol/default_page_id but no board_id. Preserve captured target and original token.
- Default values are per board, but revision combines shared storage/settings generations: a secondary mutation can invalidate the primary's old token while leaving its value unchanged. Surface412; never silently obtain a newer token for an old action.
- Sparse board PATCH is sequential/unconditioned; default_page_id PATCH is not revision-safe. Do not combine fields and call it an atomic conditional write. Test corpus demonstrates partial persistence on a later setter's failure.
- Review fixture/source scope before enabling individual operations, preserve no-replay/unknown outcome and acknowledgement/readback separation. Conditional default UI needs an original snapshot context, not a cached fresh token substituted at confirm.

## Rich editing remains mandatory for both families

Read `docs/research/2026-10-28-rich-editor-requirements.md`. Current native editor is still the bounded fixed-slot raw-template draft. It does **not** yet satisfy rich split-flap or LED parity.

Current upstream has separate split-flap TipTap and LED `charset-template-editor.tsx`/FiestaUI TemplateEditor paths. FiestaUI8.14.2 is pinned. LED includes supported color spans, block spans, icons, mixed-case/charset behavior; split-flap has its own glyph/color/tile/variable/formula behavior including filled71. Build and verify both, including rich/plain round trips, IME/paste/selection/undo, server previews, revision-safe saves/conflicts, recovery, resizing and accessibility. Raw-only LED is not an acceptable compromise.

## Method and continuation

- Approved whole-program plan: `docs/superpowers/plans/2026-10-28-native-parity-completion.md`; design and checklist linked there. User approved continuous implementation and reinforced rich split-flap + LED.
- Sol6.1 implements, Astra reviews each bounded task and integrated milestone; at most two implementers, one reviewer plus root. Use fresh scoped briefs, fixed ownership and actual evidence; no duplicate reviews spawned by workers.
- Follow review fix loops. Current Task6 is round1 of5, not a fresh implementation. Original worker identity `/root/native_connection_ui` may remain reusable after model switch, otherwise give a fresh implementer the exact diff/brief/report/review.
- Use explicit own-path staging and `git commit --only` in the shared worktree. Never capture another worker's edits. Keep ignored reports local; one report was accidentally tracked then properly untracked in bbea377.
- Retain root's uncommitted checklist/status edits; update the durable ledger after every accepted milestone. Never mark all84 workflows verified from unit tests or schema evidence.
- Deferred minors: CI wrapper failure stdout could be surfaced better; known upstream FastAPI/datetime warnings are disclosed. No blanket warning suppression.
- HA source-supported direct published endpoint first; actual authenticated ingress/native bridge proof remains open, not waived. Opus CLI previously had expired authentication; no Opus contribution claimed or blocking retry required.
- After Task6 acceptance, finish final builds/review, integrate a concrete runnable draft into main **with a backed-up semantic/byte-preserving signing overlay merge**, then offer the prepared iPhone test walkthrough while continuing remaining independent plan work. Publishing/production deployment remains separate.

## Suggested next-model instruction

Read this handoff and TASKS.md. Resume the approved native parity program in the existing foundation worktree; preserve uncommitted Task6 fixes and main signing edits. Finish and re-review Task6, review Task7-A, then implement the tested10.1.17 native control adapter and continue the approved plan. Rich editing must support both split-flap and LED. Use Sol6.1 implementation/Astra review, don't redo completed tasks, and use Safari to inspect the test server when CLI networking fails. Keep working until parity, with only indispensable device/provider interactions requested.
