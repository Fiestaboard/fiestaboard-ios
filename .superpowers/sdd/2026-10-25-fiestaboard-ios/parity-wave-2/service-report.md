# Native page services and connection-scoped actions

Implemented Task 2 of `docs/superpowers/plans/2026-10-26-page-editing.md` in the existing `codex/ios-foundation` worktree. Ownership is limited to FiestaBoardKit, FiestaBoardAppState and this report.

## Contract and interfaces

- `PageSavePatch(name:template:expectedRevision:)` encodes only the explicitly supplied changed name and/or fixed-slot template plus original revision. Empty patches/revisions fail locally. Native page writes require session opt-in and a loaded template page advertising exactly `page-revision-v1` with a nonempty revision. The separate board control gate remains non-development exact version 10.0.0.
- `FiestaBoardService.savePage(id:patch:)` returns `PageSaveReceipt` with the whole raw reply, exact lexically sliced `pageData`, and incompatible-reference count. HTTP 412 is `pageConflict`. Only HTTP 200 with a matching page/protocol and changed nonempty revision acknowledges storage. No result claims board delivery.
- `validatePage(requestData:target:)` and `previewPage(requestData:target:)` accept prebuilt lossless request bytes and concrete known boards. Validation allows template/board_id; render additionally allows device/array/grid geometry, line_metadata and canvases. Both requests are sent byte-for-byte. Unknown preview versions refuse locally; audited adapters allow non-development 10.0.0/10.1.2. Only evaluation endpoints `/templates/validate` and `/templates/render` are called. Evaluation POSTs use read/evaluation error semantics, without retries or page-write locks; `/render/live` remains classified as mutating and is never called.
- Typed validation/render projections preserve raw response bytes, syntax positions, charset/canvas warning counts, charset identity and layer presence. UI consumers retain unsupported/rich output and simulated-render labels.
- `PageDocumentSnapshot` retains id/deployment/data and adds immutable `PageEditingContext`, `editingAccess` and `incompatibleReferenceCount`. `BoardStore.savePage(patch:context:)` returns a fresh raw snapshot/context. `readbackPage(context:)` validates captured session identity before fetching. Scoped validate/preview methods reject stale replies and accept any known preview board on that deployment.

## Session and concurrency behavior

Contexts bind deployment, page, connection generation and document identity. Same-URL reconnects invalidate old contexts. Successful save/readback rotates the document context, preventing replay through obsolete snapshots. Home board selection conservatively invalidates original contexts; selecting a preview target from known boards does not require changing Home selection. The caller's recovered original revision passes unchanged; the service never silently replaces it with a background read's revision.

Duplicate/in-flight, uncertain and conflicting page writes remain locked until explicit readback. Per-page write generations prevent reads begun before a save from overwriting a later acknowledgement or clearing an uncertain write lock. Old/unknown protocols cannot produce PUTs. Authentication failure on page load/save/validate/preview disconnects the store. Existing cookie isolation, redirect refusal, timeouts, no-replay transport and board-control behavior remain intact.

Demo saves persist in memory and rotate tokens without changing board output. Rejected simulation produces a deterministic revision conflict; unknown/partial modes persist the edit then return unknown, resolved by explicit readback. Demo validation is simulated and render echoes literal lines without plugin/formula evaluation or canvas drawing. No networking/hardware is used by demo tests.

## Fidelity and fixtures

Raw page extraction validates JSON syntax with JSONDecoder without converting ignored numeric lexemes, then performs bounded top-level lexical slicing. It preserves raw UTF-8, unknown nested values, integers beyond IEEE-754, exponent spelling and extreme exponent lexemes. Escaped root keys work; duplicate decoded root keys are refused using exact decoded UTF-8 identity. Canonically equivalent but distinct Unicode scalar keys are not conflated. Existing FiestaBoardDocuments remains independent; Kit adds no Documents dependency.

`FiestaBoardKitTests/Fixtures/page-revision-v1.json` is copied from backend `tests/fixtures/page-editing/page-revision-v1.json` at backend commit `dadbc191e7b329a2803f229dcca22914e6a83b6e`. It uses source-valid panel 3×15 geometry and synthetic content. Existing 2×4 panel transport fixtures remain read-only. Endpoint metadata and geometry were checked against `src/templates/models.py` and `src/templates/routes.py`; no live deployment calls occurred.

## Verification

Tests were added before implementation. Initial missing-API failures were observed; focused behavior regressions also proved red before fixes for numeric fidelity, asynchronous save status, evaluation error classification, saved-context access, and late reads overwriting an acknowledged revision/reopening uncertain locks.

Full host package suites passed with 42 Kit tests and 32 AppState tests (74 total), including narrow body scope/original revision, Unicode/raw bytes/extreme numbers, backend fixture, old/unknown protocols, opt-in, 10.1.2 page save with board controls still read-only, HTTP 412 mapping, uncertain outcome/no replay, same-URL reconnect, duplicate saves, stale previews after page/board changes, any-known-board preview, authentication invalidation, late-read races and evaluation failure leaving page storage available.

Commands from the worktree root:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/fiestaboard-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/fiestaboard-swift-cache swift test --disable-sandbox --package-path Packages/FiestaBoardKit
CLANG_MODULE_CACHE_PATH=/private/tmp/fiestaboard-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/fiestaboard-swift-cache swift test --disable-sandbox --package-path Packages/FiestaBoardAppState
git diff --check -- Packages/FiestaBoardKit Packages/FiestaBoardAppState
```

The first plain SwiftPM attempt could not write the default global module cache. The documented writable temporary caches resolve that environment issue. SwiftPM still reports disabled user-level caches/read-only manifest-cache warnings; these do not affect compilation or test outcomes. No unresolved test failures. Combined app builds, UI checks and independent review are owned by the coordinating agent.

## Astra P1 follow-up — distinguish page context from session loss

Reviewed `astra-native-review.md` and verified the source classification defect: document ID rotation after comparison readback used the same `staleSession` error as real connection-generation loss. Added `FiestaBoardError.stalePageContext` for document-token changes and per-page write-generation invalidation in the new page service/store helpers. `pageEditingAccess` now preserves that precise disabled reason. Same-URL reconnect/connection-generation invalidation still uses `staleSession`; genuine HTTP 401 still uses `unauthenticated`. Existing board action behavior is unchanged.

Also removed the new page helpers' use of task cancellation as a proxy for session loss. A cancelled successful evaluation returns `CancellationError`, avoiding an unintended authentication-recovery checkpoint. A cancelled save retains its explicit-readback lock because the server may already have stored the captured content; cancellation never permits replay. Tests verify that readback resolves that state and the mutation happened exactly once.

Observed behavioral red failures before the fix for comparison readback expecting page-context staleness (actual session loss) and a cancelled preview expecting cancellation (actual session loss). Focused AppState checks (six existing/new affected cases) and the service late-read check passed after the change. Then ran each full package suite once: **42 FiestaBoardKit tests and 35 FiestaBoardAppState tests passed, 77 total, zero failures**. Existing same-URL reconnect and genuine 401 tests remain green. `git diff --check` is clean. Writable-cache SwiftPM warnings remain environmental; no compiler warnings or unresolved test failures. The editor owner separately covers the full preview → comparison → reload → late error draft-preservation reproduction and late-401 protection barrier.

Only the owned Kit/AppState packages, their tests, README and this report changed. The optional whitespace-only page-name policy difference is outside this P1 fix and was left unchanged.
