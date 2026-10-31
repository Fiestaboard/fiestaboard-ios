# First native flexible text and Canvas authoring slice

Implementation commits:

- `6cefa4e27fcfcdb0a7065dcf0de4ed162c8c41b9` — initial native flexible slice, immutable initial Astra review target.
- `67bc01bc6d55c207c33a92ac9eb771a76496fcb9` — preserve distinct source/destination shape focus across Undo/Redo, backed by a failing then passing regression.
- `fc07a82a1c0d5fb69db4f5378743b431c3063a37` — runtime fix round1: new flexible UI scenarios query the explicit `flexibleTextEditor` identifier and emit hierarchy diagnostics on lookup failure. Typing/value/reopen assertions and legacy template queries remain intact.

Product range: `7a96eb3..fc07a82a1c0d5fb69db4f5378743b431c3063a37`. Follow-up review diff from the initial immutable review target: `6cefa4e27fcfcdb0a7065dcf0de4ed162c8c41b9..fc07a82a1c0d5fb69db4f5378743b431c3063a37`. Original delegated base was `df6a6af838f854631a222728b412dd052a13202d`; intervening `950cb5b` and `7a96eb3` are controller documentation/acceptance commits, not changes by this implementation.

Active source is `/Users/jeffre/workspace/fiestaboard-ios-beta-recovered-20261031`, recovered and independently verified by controller (matching 1511 files, Git object validation and fsck). The original cloud checkout remains frozen. The earlier workspace availability blocker is resolved. The unfinished scripts were checked against the recovered diff, adapted explicitly to the recovered location, and applied without replaying uncertain old operations.

## Outcome and scope

Explicit `flexible` / `page-document-v2` pages now expose a real native editor for text, block structure/style/layout/targets, and Canvas content/source/shapes. Conditional storage still requires `page-revision-v1`, the captured original revision, current connection scope and session opt-in. Unknown document families/protocols remain read-only. Template-grid transport and the template-only create/delete policy remain bounded as before.

The slice reuses `PageDocument`, `LosslessJSON`, `DocumentEditingSession`, `LocalPageEditorModel`, `LocalDraftStore` and verified `DraftIdentity`. No duplicate document store, sync engine, rasterizer, backend renderer, backend edit, production operation, hardware action, runtime installation, or publication was added/performed.

Local package/fixture checks pass. Controller reported the unsigned generic iOS build and regenerated-project check passed. Actual phone/tablet runtime acceptance is still pending: the first phone run passed the mixed-library route test and failed the two new flexible journeys at a UI-test identifier mismatch (the visible native editor is identified by `flexibleTextEditor`, while the new journeys queried `templateRowText`). Controller supplied a live diagnostic screenshot and authorized a focused query fix, now committed as `fc07a82`. The rerun must still prove real typing, preview, conditional save, reopen and invalid-field behavior. No phone/tablet interaction or screenshot acceptance is claimed here.

## Public interfaces and behavior

### Documents and history

New `FlexibleEditing.swift` supplies `FlexibleLocation`, `FlexibleBlock`, `FlexibleIssue`, `FlexibleNumber`, and `FlexibleEditError`. `PageDocument` adds:

- `supportsFlexibleEditing`, `flexibleBlocks`, `flexibleShapes(blockID:)`, `flexibleValue(_:key:)`, `flexibleContainerValue(_:)`, and whole-document `flexibleIssues`.
- Bounded block insert/remove/move and text insertion at a validated captured UTF-16 selection. Generated IDs are stable, unique ASCII IDs within the core limit; retained IDs/opaque siblings are never regenerated.
- Shape insertion/remove/move, with native editing fields limited to text, rectangle, and line. Other known shape types remain retained/read-only. Unknown shape discriminators remain local and block server evaluation/replacement.
- Bounded field writes for block/style/layout/targets/Canvas/content/known shape fields, explicit container repair/inheritance, and Canvas content-size edits. Repairs require an explicit UI confirmation and are undoable.
- `flexibleEvaluationData(boardID:)`, which emits only author content plus the explicit board ID, excluding server metadata and grid-only fields.

`FlexibleNumber.draft` accepts only complete exact JSON numeric lexemes as numbers. Empty, minus, dot, trailing-dot, leading-zero, and incomplete-exponent strings remain strings in the local retained tree. They survive disk checkpoint/recovery and undo/redo; the entire document gates Save and Preview regardless of selected/collapsed block or shape. Known invalid fields remain represented for editing; malformed optional containers have explicit repair controls. Validation interprets only declared fields, retaining opaque extensions and exact number spellings. Board colors match the eight exact core keys, with the separate style/Canvas literal/expression rules.

`DocumentEditingSession.editFlexible(action:focus:undoFocus:_:)` applies a copied candidate through the existing revision/history pipeline, without rejecting recoverable numeric drafts. History now carries action labels and snapshot-appropriate affected locations (`undoActionName`, `redoActionName`, `historyFocus`), so structural/shape undo reveals the restored source and redo reveals the destination. Newly added shapes regain their inspector selection; recovery clears stale focus. Acknowledged server adoption still clears obsolete revision history. Root mutation is internal to Documents; external callers use bounded mutations.

### Transport and service

`PageSavePatch` adds explicit optional `blocksData`, `styleData`, `layoutData`, and `targetsData`. Nil omits a field; bytes `null` are explicit null for optional style/layout/targets. `blocks:null` and empty blocks are refused locally, reflecting core storage/config behavior. Flexible and legacy grid patch fields cannot be mixed. No type/grid/server-metadata root patch API exists. `serializedData()` preserves full nested array contents, unknown siblings, nulls and exact numeric lexemes; generic Encodable refuses raw-field transport to prevent lossy accidental encoding.

New `FlexiblePreviewResult` parses the actual flexible endpoint reply (`available`, `page_id: unsaved`, `message`, `lines`, `display_type`, `raw`, layout issues and optional Canvas/cells/layers). It shares the existing exact `PreviewSurface` parser; it is not a template render reply. Raw warnings are retained and readable warning messages are presented, with raw fallback for future issue shapes. Unknown physical formats never fall back to legacy rendering.

`FiestaBoardService.previewFlexiblePage(requestData:target:)`, Live service and `BoardStore.previewFlexiblePage(requestData:context:target:)` provide the evaluation route. Default adapters refuse unsupported evaluation. Permission derives from explicit flexible-v2 document support, independently of the legacy evaluation version bound. A template context cannot acquire flexible evaluation permission. Service verifies deployment, exact current known target/body board ID and author-field shape before dispatch. Store validates document/session/target context before and after await.

The exact `POST /pages/preview/flexible` request is read-only evaluation in `APIRequest.isMutation`; neighboring paths/methods remain mutations. Timeout/offline/404/422 evaluation failures never become unknown page-write outcomes. Native requests always specify a selected board. Core pin is `864cfa6baccdf5b9f29db712442bf40fb3e79923`: explicit unknown or empty target returns404; omitted/null keeps primary default only for other callers. Native never asks for that default. The response does not echo the target, so UI labels the requested target without claiming an independently verified target echo or physical display output.

Live page reads retain complete raw bytes for merged flexible validation. A flexible save checks the whole outgoing merged document as well as the allowlisted sparse patch. Server/service/session gates, original revision, no automatic412 replay, and unknown-outcome readback locks remain active. Editor dirty state covers all flexible author fields; receipt adoption verifies family/protocol/new revision. Server status means acknowledged snapshot: editing immediately produces Unsaved; Saving/Conflict/Unknown/Comparison are distinct. Local checkpoint state remains separate.

### Native UI

New `FlexibleWorkspaceView` offers an adaptive native block list and bounded inspector, with `AnyLayout` preserving child identity as width changes. Text uses the existing TextKit bridge, native selection/IME/paste and source-preserving token handling. Variable/expression insertion captures the source selection after committing input; it never blindly appends. Flexible text disables UITextView’s separate undo stack and uses the document toolbar/keyboard shortcuts, avoiding a second undo of the same text operation. Template bridge defaults remain unchanged.

Canvas has explicit Drawing/Source expression selection while retaining drawing fallback, editable width/height/background, shape list/selection and text/rectangle/line inspectors. Position, size, line endpoints/width, colors and fonts have native fields and accessible adjustment buttons. Add/remove/reorder actions are native menus/buttons with undo outcomes. Other known shapes, pixel rows, palettes and opaque extensions are retained. Layout and Canvas warnings appear beside the server preview. A visible issue route selects the affected block/shape, opens styles when needed, scrolls and focuses the field. The surrounding Form scrolls controls above the keyboard and preserves the same editor model across width changes.

## Changed files / project integration

The initial implementation commit changes27 explicit files (1954 insertions,100 deletions); the two focused follow-ups touch only paths already listed:

- Native: new `App/Features/Editor/FlexibleWorkspaceView.swift`; existing `LocalPageEditorView.swift`, `NativeTemplateTextView.swift`, `LocalPageEditorLoader.swift`, `PageDetailView.swift`.
- Documents: new `FlexibleEditing.swift`; `PageDocument.swift`, `DocumentEditingSession.swift`; new Documents `FlexibleEditingTests.swift`.
- Kit: `Package.swift`, `CapabilityPolicy.swift`, `PageEditing.swift`, `Service.swift`, `Transport.swift`; new Kit `FlexibleEditingTests.swift`, `FlexibleServiceTests.swift`.
- EditorState: `EditorRemoteActions.swift`, `LocalPageEditorModel.swift`, `EditorTests.swift`; new `FlexibleModelTests.swift`, `FlexiblePreviewRaceTests.swift`.
- AppState: `BoardStore.swift`, `BoardStoreTests.swift`.
- Fixtures/UI: `Tests/UITests/fixture_server.py`, `DemoUITests.swift`; new `Tests/Contracts/test_flexible_editor_fixture.py`.
- `project.yml`: Kit now depends on Documents.

Controller regenerated `FiestaBoard.xcodeproj/project.pbxproj`, verified `scripts/check-project.py`, and owns that separate uncommitted generated-project change. It adds only the two new source entries and Kit→Documents dependency. It was deliberately excluded from the implementation commit as instructed; controller must include it in integration. Controller docs/ledgers were likewise excluded.

## Regression evidence

Evidence logs are copied to `../mobile-beta-discovery/evidence/flexible-editor/` relative to the recovered checkout. Original scratch logs remain in `/tmp`. No Docker/backend/production integration test was run by this implementer.

Full final suites:

| Scope | Count | Result | Evidence log |
| --- | ---: | --- | --- |
| Documents |48|0 failures|`fb-flexible-history-final.log`|
| Kit |176|0 failures|`fb-flexible-recovered-kit-final.log`|
| EditorState |65|0 failures|`fb-flexible-shape-focus-green.log`|
| AppState |96|0 failures|`fb-flexible-recovered-appstate-green.log`|
| Python contract/fixture tests |62|OK|`fb-flexible-contracts-green.log`|
| Python tooling tests |15|OK|`fb-flexible-tooling-final.log`|

The six new synthetic flexible fixture tests are included in Contracts62; their isolated run is `fb-flexible-fixture-green.log`. Swift source parsing for the native editor and UI tests passed. `git diff --check` and staged diff checks passed before the implementation commit. Controller independently reported unsigned generic-device build PASS, with normal no-AppIntents metadata warnings; this is controller evidence, not a simulator or hardware result from the implementer.

Commands (from active recovered checkout):

```sh
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardDocuments --scratch-path /tmp/fb-flexible-recovered-documents
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardKit --scratch-path /tmp/fb-flexible-recovered-kit
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardEditorState --scratch-path /tmp/fb-flexible-recovered-editor
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardAppState --scratch-path /tmp/fb-flexible-recovered-appstate
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/Contracts
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/Tooling
swiftc -parse App/Features/Editor/FlexibleWorkspaceView.swift App/Features/Editor/LocalPageEditorView.swift App/Features/Editor/NativeTemplateTextView.swift Tests/UITests/DemoUITests.swift
```

Observed red-to-green evidence includes: exact flexible POST initially classified as a mutation; deleted-target reply after a local edit failed3 assertions; existing fixture lacked the native flexible GET/preview/conditional PUT (6 failures); template context incorrectly acquired flexible preview (1 failure); whole retained-known-field validation/core purple alias tests failed16 assertions. These behaviors were corrected and full suites rerun. A final shape-reorder regression then failed1 source-index focus assertion; `67bc01b` corrected it, followed by full Documents48/48 and EditorState65/65 runs. New API/history/repair tests also initially failed compilation because their interfaces were absent; logs explicitly preserve that distinction. Interrupted old Kit run (172 tests,4 failures) and Service392 compile error were reconciled; no failure from those runs remains in the final full suites.

Coverage includes large integer900719925474099312345678 through nested whole-array replacement; null/omission/extensions/stable IDs/no grid leakage; read/edit/preview/conditional save/reopen; original revision and412/unknown-outcome no replay; unknown protocol/shape refusal; block/shape structure and history; captured UTF16 expression insertion; invalid numeric intermediates/checkpoint/recovery/hidden repair; immediate Saved→Unsaved; target/document/session/out-of-order preview rejection and in-flight deletion preserving newer edits.

Native UI tests added actual text/Canvas edit→preview→save→reopen, width-change retention, screenshot attachments, and an invalid hidden Canvas journey that first establishes enabled Save/Preview with valid dirty text, then proves invalid-field gating before/after selection changes and through Undo/Redo. Existing mixed-library regression now allows explicit v2 and retains future-protocol refusal. Controller owns execution and acceptance; first identifier mismatch was fixed narrowly in `fc07a82`, with runtime rerun pending rather than waived.

## Limits / remaining integration

This is the first executable slice, not broader editor parity. Brush painting, palette/catalog authoring and native editing for circle/ellipse/polygon/gradient remain explicitly outside this slice; those known values/pixels/palettes are retained read-only. Unknown shape types block whole-document save/preview until explicitly removed or support is verified. No rasterizer/renderer port exists; server preview is authoritative evaluation.

The loopback fixture is synthetic, pinned to the reviewed source contract. Its physical image is deterministic test artwork, not a backend rendering/hardware observation. The core change is not assumed deployed anywhere. Legacy rich overlays without a supported physical full frame retain raw data and a web-inspection note; no visual parity claim is made.

Remaining actions: controller commits generated project integration, reruns the fixed flexible text control queries with real typing/value assertions, completes meaningful phone/tablet journeys/screenshots, and performs independent Astra review of both the immutable initial change and focused follow-ups. Fold/runtime27.1 validation is not claimed. No installation/publication/physical-device/backend permission blocker remains; the outstanding acceptance is runtime/review work already assigned to controller.
