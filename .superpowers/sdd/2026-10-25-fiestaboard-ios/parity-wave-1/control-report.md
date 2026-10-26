# C-01 Board controls report

Implemented in the foundation worktree, based on e07605a. No main-checkout, signing, project or AppRoot edits.

## Source contract

Pinned `.reference/FiestaBoard-v10/src/v1/models.py` (`BoardUpdate`, `RestoreResponse`) and `src/v1/routes_boards.py` (`update_board`, `restore_board`) support:

- `PATCH /api/v1/boards/{concreteID}` for `paused`, `schedule_enabled`, `auto_restore`, and `default_page_id`. `BoardPatch` encodes only explicit fields. `.omit`, `.set(id)`, `.clear` distinguish omission from JSON null. No name or unrelated settings are reset.
- PATCH returns `BoardDetail`; `BoardConfigurationReceipt` acknowledges configuration only, never a hardware send. The paused/schedule/auto-restore/default projections remain separate from active, scheduled, resolved and reported characters.
- `POST /api/v1/boards/{concreteID}/restore`, no request body. `BoardRestoreReceipt` decodes `board_id`, `page_id`, `sent`, `reason`, `device_observed`. The pinned page is retained; restore follows the currently intended timed/scheduled/pinned content. Paused and silenced boards refuse with 409; UI-only installs can return `sent:false`. There is no invented return-to-schedule endpoint or unpin shortcut.
- Restore request timeout is 300 seconds and session resource timeout is 300 seconds. The pinned send executor documents serialized sends and transitions up to 120 seconds; a queued restore can exceed the old 20/30-second defaults. Timeout still means unknown outcome and never causes replay.

Only the exact opted-in non-dev running version `10.0.0` gains candidate writes. Unknown and 9.x versions stay read-only. Target/deployment validation and request-generation checks remain in the shared service path. Mutation requests remain single-attempt.

PATCH setters run sequentially, so even an explicit error may follow an applied field. The store requires readback after every failed configuration action, and after uncertain/partial restore outcomes. Successful actions refresh the snapshot, including the board list summary. Receipts survive failed readback. Existing immutable target/generation confirmations and used-action/in-flight sets apply to new actions.

Demo configuration updates persist in memory and keep the list/detail coherent. Pausing blocks sends/restores; schedule changes resolve expected selection without changing reported characters. Restore does not unpin. Simulated held restore refuses as silence, and unknown configuration changes can be observed only after refresh.

## Public integration

`BoardControlsView(store: store)` is an app-internal native SwiftUI Section intended inside Home/Display detail Form/List. It owns its confirmation dialog and calls the existing `BoardStore.prepare` / `confirm`. It offers pause/resume, schedule on/off, auto restore, fallback set/clear, restore. The immutable confirmation names the captured board and deployment. Root must add this file to project generation and insert the Section.

`ActionPayload` gained `.configuration(BoardPatch)` and `.restore`; existing exhaustive switches in AppRoot need these cases. `BoardPatch(paused:scheduleEnabled:autoRestore:defaultPage:)` and receipt types live in FiestaBoardKit. No Documents dependency was added.

For the local editor integration, `FiestaBoardService.pageDocumentData(id:) async throws -> Data` returns exact public GET response bytes, validates identity, and does not re-encode the lossy Page projection. `BoardStore.loadPageDocument(id:) async throws -> PageDocumentSnapshot` returns immutable `id`, `deployment`, `data`. It checks current page membership, captures generation/deployment, rejects late old-connection responses, and disconnects on 401. The editor can consume the Data and bind its local draft to deployment/page identity. This is read-only.

## Verification

Tests were added and run before their missing production APIs, producing expected compiler failures for absent BoardPatch/control/raw-document APIs. Subsequent complete package suites pass:

```
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" swift test --package-path Packages/FiestaBoardKit --disable-sandbox --scratch-path .build/control-kit
# 29 tests, 0 failures

env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" swift test --package-path Packages/FiestaBoardAppState --disable-sandbox --scratch-path .build/control-state
# 23 tests, 0 failures

xcrun swiftc -typecheck App/Features/Control/BoardControlsView.swift -target arm64-apple-macos15.0 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -I .build/control-state/out/Products/Debug -module-cache-path .build/control-view-module
# exit 0
```

Coverage includes sparse encoding/default clear, pause/unpause/schedule/auto restore, selection preservation, held/refused restore, unknown/invalid receipts, wrong scope/board, unknown-version write refusal, stale confirmations/results, duplicate suppression, failed PATCH readback lock, raw byte preservation, stale document generation and document 401 invalidation. Existing transport/session regression tests also pass. SwiftPM emitted expected inaccessible global-cache warnings under the workspace sandbox; build/test commands succeeded. Logs are under `.build/control-evidence/` (local, ignored). `git diff --check` passed.

## Actual Claude Opus CLI evidence

An actual meaningful read-only source-contract review was attempted with included pinned routes/models/send-executor plus service/store source. The prompt requested concrete recommendations on partial PATCH, restore receipts/timeouts, and generation/no-replay behavior. Exact invocation:

```
claude -p --model opus --no-session-persistence --strict-mcp-config --safe-mode --tools '' --allowedTools '' --max-budget-usd 4 --output-format json < .superpowers/sdd/2026-10-25-fiestaboard-ios/parity-wave-1/control-opus-prompt.txt > .superpowers/sdd/2026-10-25-fiestaboard-ios/parity-wave-1/control-opus-output.json
```

Exit 1. Output reports `api_error_status:401`, `terminal_reason:"api_error"`, `duration_api_ms:0`, `modelUsage:{}`, zero tokens and cost, and: `Failed to authenticate. API Error: 401 OAuth access token has expired. Re-authenticate to continue.` No Claude contribution was produced or claimed. The actual JSON result is retained beside this report. Normal permissions were used; no credential reads/copies, authentication changes, permission bypass, MCP or retry occurred. The coordinator was notified promptly; Sol completed the implementation as instructed.

## Remaining limits

Source fixtures are candidate evidence, not proof of deployed server support. No production/hardware calls occurred. This task does not claim full product parity/release readiness. Root still owns project/AppRoot integration and the final iOS simulator build/visual review. Standalone SwiftUI verification here is macOS typecheck, not rendered iOS QA. Claude review remains unavailable until the user renews its expired login. No new collaboration subagents were started.
