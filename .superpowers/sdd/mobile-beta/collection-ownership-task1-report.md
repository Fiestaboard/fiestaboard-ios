# Collection ownership Task1 implementation report

Status: Task1 implemented and package-verified; independent controller/Astra review pending. Task2 inventory/export has not started.

## Immutable review range

- Authorized task baseline: `de8c14035fbdead5dba059b4bc1047785d6412b7`.
- Product commit: `0dcbebb` — Bind collection drafts to verified connection ownership.
- Exact product-only review range: `dbde96e..0dcbebb` (12 files). Controller docs/native acceptance commits advanced HEAD after the task baseline; they are not part of this product change.
- Active repository: `/Users/jeffre/workspace/fiestaboard-ios-beta-recovered-20261031`. Frozen Documents checkout untouched.

## Interfaces and behavior

`ScopedCollectionDocument` carries `PageCollection?` and `VerifiedConnectionScope`. `FiestaBoardService.scopedCollectionDocument(id:)` has a refusing default; Live captures its existing verified scope/service generation before the optional read and checks both plus transport connection ownership after awaits. A nil-ID creation requires the same verified ownership. Demo delegates its existing explicit scope. No username, credentials or new vault contract is used.

`CollectionEditingContext` captures scope and `CollectionEditorSnapshot` exposes it. BoardStore obtains content/scope together, revalidates after library/access reads, and retains live generation, document tokens, original revision, write epochs and consumed-create/readback guards. Save/delete/compare check ownership before dispatch; late receipts/comparisons are checked against the original scope. Reconnect with the same durable scope still invalidates old live contexts.

`CollectionDraftIdentity` stores deployment, installation ID, connection UUID and optional collection ID. Its fields are immutable; UTF-8 exact equality/hashing distinguish canonical-equivalent strings and nil from any ID. Model scope fields remain captured for every preservation/error callback. Only an acknowledged creation transitions the optional resource ID inside that same scope.

Checkpoints use format version2 and an explicit identity. Legacy deployment-only files remain unassigned. Active load validates the complete identity, mirrored resource/deployment fields and baseline ID. Recovery re-reads the selected file and verifies both current ownership and exact SHA-256 version before installing the saved original baseline/revision. Interrupted writes remain unknown and cannot automatically replay. Persisted `sourceSupportsEditing` retains the existing unsupported/unknown-field read-only guard despite typed projection encoding.

Lineage entries are untrusted: eligibility checks current file identity, supported version, UUID filename and SHA-256 bytes before inheritance and again before retirement. Discard, full revert and acknowledgement use independent exact-version markers; original JSON bytes remain intact. Foreign, legacy, malformed, future and newer same-UUID versions cannot be retired through serialized lineage. Successful creation attempts retirement under the old nil-ID identity before adopting the receipt ID; subsequent edits/restarts recover under the assigned ID. If local marker writing fails after server acknowledgement, the acknowledgement remains final, a cleanup message is shown, and surviving interrupted-create material remains unknown/non-replayable.

## Owned files

- Kit: `Service.swift`, `CollectionEditing.swift`, `DemoService.swift`, `SessionPersistenceTests.swift`.
- AppState: `CollectionContext.swift`, collection operations in `BoardStore.swift`, `CollectionStoreTests.swift`, `ConnectionModelTests.swift`.
- EditorState: `CollectionDraft.swift`, `CollectionEditorModel.swift`, `CollectionEditorTests.swift`.
- App: collection loader in `App/Features/Collections/CollectionsView.swift` passes the verified snapshot identity.

No flexible editor/native UI tests, generated project, server, software, security or sync settings were changed. No native/simulator/physical-device actions were run by this implementer.

## Regression evidence and corrections

Evidence root: `/Users/jeffre/workspace/mobile-beta-discovery/evidence/collection-ownership-task1/`. Original logs also remain in `/tmp` with the same filenames.

- `fb-collection-unassigned-red.log`: pre-implementation behavioral regression `testUnassignedCheckpointCannotEnterActiveRecovery` failed (1 test,1 failure); deployment-only material entered active recovery. Now covered and green.
- `fb-collection-identity-red.log` and `fb-collection-kit-red.log`: expected missing-new-interface compilation failures while introducing the scoped APIs; the early Kit log also includes a test-only optional-cookie mismatch corrected before executing it. These are compilation evidence, not claimed behavioral red tests.
- `fb-collection-preflight-red.log`: `testReplacedOwnershipCannotDispatchOriginalContextSaveDeleteOrCompare` failed (1 test,2 assertions): update/delete dispatched once under replaced ownership despite later receipt rejection. Added the pre-dispatch scope check and retained reentrant context/barrier checks. Final complete AppState suite passes, including this test and late comparison/save coverage.
- `fb-collection-appstate-green.log` is intentionally preserved despite its historical filename: 96 tests,1 unexpected `invalidPath` at BoardStore727. The synthetic collection UUID omitted the contract-required `collection:` prefix. Corrected the fixture route and IDs; production path validation was unchanged. Final real auth-disabled ConnectionModel → LiveService → URLSessionTransport → BoardStore coverage passes.
- `fb-collection-kit-green.log` is an incomplete earlier run, not a pass: the same invalid synthetic ID prevented the delayed request from reaching its gate. Task-owned test session58693 was canceled (exit130); no uncertain mutation. Correcting fixture IDs and the gated endpoint made the final full suite terminate normally.
- `fb-collection-editor-initial.log` and `fb-collection-editor-green.log` record intermediate complete71/71 and75/75 runs. Additional exact-string/overwrite regressions bring the final EditorState count to77.

Added/retained coverage includes verified creation/read scope, remembered restore, same-username fresh login, changed installation, invalid old transport lease, late scoped reads, same-scope reconnect with stale live context, exact Unicode ownership, nil creation isolation, original revision/invalid text recovery, unknown-create non-replay, unknown-field read-only recovery, cached-choice replacement, malformed/future/legacy byte preservation, forged lineage, newer same-UUID sources, concurrent recovered editors, acknowledgement→assigned-ID edit→restart, and archive overwrite refusal.

## Final verification

All commands ran from the active repository with the installed toolchain and isolated `/tmp` build/module caches. For each package the command was:

```sh
SWIFT_MODULECACHE_PATH=/tmp/fb-collection-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-collection-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardKit --scratch-path /tmp/fb-collection-kit > /tmp/fb-collection-kit-final.log 2>&1
SWIFT_MODULECACHE_PATH=/tmp/fb-collection-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-collection-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardAppState --scratch-path /tmp/fb-collection-appstate > /tmp/fb-collection-appstate-final.log 2>&1
SWIFT_MODULECACHE_PATH=/tmp/fb-collection-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-collection-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardEditorState --scratch-path /tmp/fb-collection-editor > /tmp/fb-collection-editor-final.log 2>&1
swiftc -parse App/Features/Collections/CollectionsView.swift
git diff --check
```

| Check | Result | Evidence |
| --- | --- | --- |
| Kit full package | exit0,178 tests,0 failures | `fb-collection-kit-final.log`, `.exit` |
| AppState full package | exit0,98 tests,0 failures (13 CollectionStore) | `fb-collection-appstate-final.log`, `.exit` |
| EditorState full package | exit0,77 tests,0 failures (43 CollectionEditor) | `fb-collection-editor-final.log`, `.exit` |
| Collection loader parse | exit0 | `fb-collection-loader-parse.log`, `.exit` |
| Whitespace/diff check | exit0 | `git diff --check` |

Total:353 affected Swift package tests passed. Final process completion receipts were observed directly (Kit session71693, AppState11849, EditorState84029, all exit0); matching `.exit` files contain0. No unrelated Python suites were repeated.

## Review limits and handoff

This task does not add collection inventory/export; original legacy/malformed/future/retired bytes are preserved for Task2. Controller owns native build/runtime acceptance and the independent review gate before Task2. Typed collection support remains conservative; no full raw collection parity or protocol expansion is claimed. Local cleanup failure after an acknowledged mutation is explicitly surfaced and never causes replay. No filesystem/permission blocker remains, and no uncertain task-owned process or mutation remains outstanding.
