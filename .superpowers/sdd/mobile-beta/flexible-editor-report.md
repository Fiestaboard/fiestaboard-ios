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


## Independent Astra review — fix round 1

Both important findings in `flexible-editor-review-report.md` were reproduced and corrected in `f62de6c9ecfa2b5636463e7bf06276f3f3ad9ad3`. Exact round source range: `0015173a32fc8881b6efffb73bddddae839fe949..f62de6c9ecfa2b5636463e7bf06276f3f3ad9ad3`. This round changes only two product files and three regression files, preserving controller-owned project changes and all native/fixture/UI source.

1. Target errors now carry ownership through a separate request/selection counter. New evaluation requests, board selection changes and session end supersede prior target evidence; ordinary draft edits do not. A delayed404 or invalidTarget from A cannot clear B's newer accepted preview or affect a selection that moved away and back. The latest deleted-target failure after a local edit still removes the unavailable target, clears stale preview and preserves the newer draft. Existing document-revision/pixel acceptance checks remain intact.
2. Page/block color and background validation now matches core864cfa6b’s single-expression DOTALL grammar with an ICU scoped `(?s:...)` group. Exact LF/CRLF text is preserved through retained document reopen, preview author bytes and whole-block sparse patch serialization. Multiple expressions, nested delimiters and prefixed expression strings remain rejected. A valid retained multiline style no longer blocks unrelated text save/preview eligibility.

Before implementation, the full Documents run had50 tests with2 failures (1 unexpected invalidDocument error), and the full EditorState run had69 tests with22 assertion failures. These failures reproduced both the compatibility and stale-error branches. After correction, full Documents50/50, EditorState69/69 and Kit176/176 pass. The existing deletion-after-edit404 regression remains green, with added latest-invalidTarget-after-edit coverage. Other existing suite evidence (AppState96, Contracts62, Tooling15) is unchanged by this round and was not redundantly rerun.

An intermediate attempt to supply a DOTALL flag as a String.range CompareOptions value failed compilation in controller's phone build (`/tmp/fb-ios-flexible-evidence/ui-phone-2.log`, exit65; no UI ran). The committed correction uses the scoped ICU grammar and was actually compiled and tested before the next stable-source handoff. It contains no nonexistent Foundation option.

Exact verification commands from the active recovered checkout:

```sh
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardDocuments --scratch-path /tmp/fb-flexible-recovered-documents > /tmp/fb-flexible-review-r1-documents-green.log 2>&1
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardEditorState --scratch-path /tmp/fb-flexible-recovered-editor > /tmp/fb-flexible-review-r1-editor-green.log 2>&1
SWIFT_MODULECACHE_PATH=/tmp/fb-flexible-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-flexible-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardKit --scratch-path /tmp/fb-flexible-recovered-kit > /tmp/fb-flexible-review-r1-kit-green.log 2>&1
```

All three commands exited0 with zero failures. Red logs are `/tmp/fb-flexible-review-r1-documents-red.log` and `/tmp/fb-flexible-review-r1-editor-red.log`. Copies of all five red/green logs are in `../mobile-beta-discovery/evidence/flexible-editor/`. `git diff --check` and staged checks passed before the source commit. No simulator/build execution was performed by this implementer.

Runtime follow-up is still open. Controller’s phone3 run supplied decisive accessibility evidence that the new enclosing `flexibleInspector` identifier propagates to its descendants and hides the intended leaf IDs. This is separate from the two Astra findings and the earlier query-only correction; it will receive a narrow native identifier-ownership fix and fresh controller runtime verification. Phone/tablet acceptance is not claimed by this round.


## Native runtime accessibility ownership follow-up

Controller's phone3 run ended65 with both selected flexible journeys failing the text-editor lookup. Its actual AX hierarchy (`/tmp/fb-ios-flexible-evidence/ui-phone-3.log`, lines1019–1042) showed the visible TextView with label `Block text` and value `Native flexible text`, but identifier `flexibleInspector`; surrounding buttons and numeric fields inherited that same enclosing identifier. This established a product identifier-propagation issue rather than evidence that the editor was absent.

Commit `53c281c2f1515c01d4328741a8664a5aa006d63e` removes only the four enclosing AX identifiers in `FlexibleWorkspaceView`: `flexibleInspector`, `canvasInspector`, `canvasShapeInspector`, and `flexibleIssues`. The last had the same risk of hiding individual issue-button IDs. All existing `.id(...)` scroll anchors, leaf control identifiers, labels, typing/value/reopen assertions and behavior are retained. No fixture, protocol, renderer, unrelated control or test assertion was changed. Source range is `d94d661b28b6a027e81178780392e9c3411b85d0..53c281c2f1515c01d4328741a8664a5aa006d63e`.

Actual parser verification exited0 with no diagnostics:

```sh
swiftc -parse App/Features/Editor/FlexibleWorkspaceView.swift App/Features/Editor/LocalPageEditorView.swift App/Features/Editor/NativeTemplateTextView.swift Tests/UITests/DemoUITests.swift > /tmp/fb-flexible-runtime-identifiers-parse.log 2>&1
```

The parse log is also copied to `../mobile-beta-discovery/evidence/flexible-editor/`. `git diff --check` and staged checks passed before the commit. The latest affected-package evidence remains Documents50/50, EditorState69/69 and Kit176/176 from the preceding review-fix round; four AX-modifier removals do not justify repeating unrelated package suites. Controller owns native rebuild and real phone/tablet reruns to verify the leaf TextView/shape/field identities through actual editing, preview/save/reopen and hidden-field repair. Those runtime results remain pending; no runtime acceptance is inferred from parser success.


## Native runtime fix round 2 — isolated Form actions

Base `d496f7c` includes the controller-owned generated-project integration. Controller reported Astra's round1 source findings passed. Phone4 then reached actual text typing, but its Hide keyboard tap at31.43s (`/tmp/fb-ios-flexible-evidence/ui-phone-4.log`) was followed by an unintended expression sheet (Cancel/Insert controls) and expanded block/page style disclosures; the evaluation picker was consequently blocked. iPad1 likewise reached text typing, then failed because both the system keyboard and app action share the accessible label Hide keyboard (`/tmp/fb-ios-flexible-evidence/ui-ipad-1.log`, lines1932 and2164). Both original runs ended65. Controller preserved native evidence under `../mobile-beta-discovery/evidence/flexible-editor/native/`.

Source inspection found `FlexibleWorkspaceView` is a single Form row with many default automatic sibling Button actions. Only its block rows had explicit plain styling; the working legacy TemplateWorkspace multibutton groups explicitly use a nonautomatic style. The narrow action-isolation correction is `4ca5a6173f2d4e4dd08c279adddb54facc18487a`, range `d496f7c..4ca5a6173f2d4e4dd08c279adddb54facc18487a`:

- Apply `.buttonStyle(.borderless)` at the flexible workspace's root so every text/Canvas/adjustment/repair action resolves independently inside the Form row. Existing plain block-row styling, native control types, scroll anchors and leaf IDs are retained.
- Give the app's Hide keyboard action a distinct leaf ID, `flexibleHideKeyboard`. Only the two new flexible scenarios use it; legacy tests and labels remain unchanged.
- Before proceeding, those journeys assert the keyboard is gone, the expression sheet is absent, exact entered text and the selected block are unchanged, and block/page style controls remain collapsed. No typing/value/reopen or invalid-hidden-field assertions were removed.
- The existing Canvas journey now increments rectangle Width from10 to11 while checking X stays2 and no remove/expression presentation occurs, then uses Undo to restore10 before continuing its original typed101/preview/save/reopen assertions. This directly exercises the same multibutton-row isolation for Canvas controls.

Only `FlexibleWorkspaceView.swift` and the existing `DemoUITests.swift` changed (36 insertions,3 deletions). No model, transport, fixture, protocol, unrelated control or project settings changed.

Actual native/UI parser verification exited0 with no diagnostics:

```sh
swiftc -parse App/Features/Editor/FlexibleWorkspaceView.swift App/Features/Editor/LocalPageEditorView.swift App/Features/Editor/NativeTemplateTextView.swift Tests/UITests/DemoUITests.swift > /tmp/fb-flexible-runtime-actions-parse.log 2>&1
```

The parse log is copied to `../mobile-beta-discovery/evidence/flexible-editor/`. `git diff --check` and staged checks passed before commit. The preceding pure-package results (Documents50, EditorState69, Kit176) remain the applicable model/service evidence; this round's behavior requires the controller's real phone/tablet rerun, not redundant unrelated package tests. Source was handed back stable for that native rebuild/rerun; no runtime success is claimed before those results. No filesystem, approval or tool-access blocker remains.


## Native runtime test correction round 3 — actual caret result

Controller's phone5 and iPad2 runs passed the hidden-invalid/repair/undo journey (phone134.765s, iPad101.430s). Both main journeys completed real text/Canvas editing, width adjustment and Undo, preview, acknowledged conditional save and reopen; each then failed only the hard-coded reopened-width assertion: expected101, actual110. Evidence is `/tmp/fb-ios-flexible-evidence/ui-phone-5.log` and `/tmp/fb-ios-flexible-evidence/ui-ipad-2.log`. The real native caret landed inside the existing10, so typing1 produced110 and the saved/reopened value correctly retained110.

Test-only commit `32e91c4fa47f0d1980d5465daa8e42c5b0da0eed` leaves `width.tap(); width.typeText("1")` intact. Immediately afterward it captures `typedWidth` and requires one of the exact valid insertion results101 or110; this excludes unchanged10, invalid numeric strings, arbitrary nonempty text and other values. It also rechecks X remains2. Reopen must equal that exact captured value. Earlier deterministic10→11→Undo10, text retention, preview/save acknowledgement gates, keyboard isolation and hidden-invalid assertions remain intact. Product behavior and native caret placement are unchanged.

`swiftc -parse Tests/UITests/DemoUITests.swift` exited0 with no diagnostics; output is `/tmp/fb-flexible-runtime-width-parse.log`, also copied into `../mobile-beta-discovery/evidence/flexible-editor/`. `git diff --check` and staged checks passed. The only source delta is4 insertions/1 deletion in the existing UI test file. Controller will rerun only the failed main journey per device; the already-passing hidden journey does not need repetition absent relevant changes. Full end-to-end runtime acceptance awaits those two corrected runs.


## Native runtime/UX fix round 4 — persistent visible field names

Reviewed `runtime-round3-and-ux-review.md` and directly inspected the supplied iPad Canvas and phone text screenshots. Populated native TextFields showed values without field names because placeholders disappear. Product/UI commit `21a01852f82d7a8d7efb5995a61d98e74d513ff0` corrects this in `App/Features/Editor/FlexibleWorkspaceView.swift` and `Tests/UITests/DemoUITests.swift` only.

The shared draftField, targetField and contentSize helpers now place a persistent native Text label above the existing control. Canvas dimensions explicitly say Canvas Width/Canvas Height. This covers positions, dimensions, background/fill/stroke, shape text/color, conditions/priority, styles, source and target restrictions. Block text and the expression sheet also have visible labels. Labels use a wrapping subheadline and stacked layout; shape adjustment buttons align to the value baseline. No new enclosing accessibility IDs or grouping were added. Existing leaf identifiers, accessibility labels, focus bindings, scroll anchors, borderless actions, numeric draft conversion, model/history and save behavior remain unchanged.

The existing main native journey adds assertions that labels and exact populated values are simultaneously hittable. It types a white block color and the synthetic contract-board target restriction, inspects Canvas dimensions/background and text-shape fields, then retains the existing rectangle 10→11→Undo10 with unchanged X2, actual typing/captured width, preview/acknowledgement and exact reopen assertions. Screenshot attachments cover populated style/target fields with keyboard, Canvas dimensions/background, text shape, rectangle, focused edited Width and reopened Width. The hidden-invalid repair journey additionally checks the focused Width label is visible. Existing typing/action-isolation/gating assertions were not removed. These UI additions are authored, not yet runtime-passed; the prior screenshots are observed defect evidence, not a red execution of the new assertions.

Exact validation command from the active recovered checkout:

```sh
swiftc -parse App/Features/Editor/FlexibleWorkspaceView.swift App/Features/Editor/LocalPageEditorView.swift App/Features/Editor/NativeTemplateTextView.swift Tests/UITests/DemoUITests.swift > /tmp/fb-flexible-visible-labels-parse.log 2>&1
```

Final parser invocation exited0 with no diagnostics (empty log); the wrapper printed `swiftc_parse_exit=0`. `git diff --check` and `git diff --cached --check` both exited0 with no output before the source commit. No simulator commands, native build, package suites or Python suites were run by this implementer. Controller owns native compilation and fresh phone/tablet main and hidden-invalid journeys, screenshot review and aggregate acceptance. The existing391 Swift/77 Python results are not recast as fresh results for this round. Dynamic Type and keyboard layout acceptance remain pending actual runtime evidence. No approval/access blocker remains; unrelated `docs/mobile-beta/collection-ownership-plan.md` was left untouched and uncommitted.


### Round 4 runtime correction — reachable keyboard dismissal

Controller phone7 (`/tmp/fb-ios-flexible-evidence/ui-phone-7.log`) failed both flexible journeys at keyboard dismissal after the label change. The hidden journey typed text, swiped the Form and tapped the inline action at33.15s, but the keyboard remained. The AX hierarchy puts the visible text viewport at y574 with35pt height, the inline dismissal at y736, and the keyboard at y653. Persistent labels increased inspector height; an action inside that scrolling content was no longer reliably reachable above the keyboard. Controller reports iPad4's hidden journey passed, and source label review passed; neither establishes phone acceptance.

Product/UI commit `1ba64e8428ea32a3766f85acc8988597f629d14f` moves the existing Hide keyboard action from FlexibleWorkspaceView to LocalPageEditorView's fixed native top toolbar, only for flexible pages. It retains the single leaf ID `flexibleHideKeyboard` and uses the existing commitTextInput responder path. This serves UIKit block text and SwiftUI numeric/style/target fields independently of inspector scrolling, with no dual accessory ownership. Labels, bindings, focus, model state, history and borderless Form action isolation remain unchanged; no NativeTemplateTextView change was needed.

DemoUITests now requires the keyboard to exist, exactly one app dismissal action to exist and be directly hittable without reveal/swipes, and the keyboard to disappear without expression or Close confirmation presentation. The existing exact text/selection/collapsed-style assertions remain. Style and target edits explicitly dismiss through the toolbar and retain exact values. The main numeric journey replaces its Close/Keep editing workaround with toolbar dismissal and requires the captured numeric draft, X2 and Canvas selection to remain. The hidden-invalid journey likewise captures a nonnil exact invalid string, dismisses through the toolbar and requires that string and Canvas selection to remain before its existing preview/save/repair/Undo/Redo checks.

Final command after all edits, from the recovered repository:

```sh
swiftc -parse App/Features/Editor/FlexibleWorkspaceView.swift App/Features/Editor/LocalPageEditorView.swift App/Features/Editor/NativeTemplateTextView.swift Tests/UITests/DemoUITests.swift > /tmp/fb-flexible-fixed-keyboard-parse.log 2>&1
```

The command exited0 with no diagnostics (empty log); both unstaged and staged diff checks exited0. No native build or simulator run was performed by this implementer. Source was handed back stable at the exact commit above for controller compilation, phone/tablet reruns and screenshot acceptance. This is a narrow correction within round4; keyboard/runtime success is pending those fresh runs. No remaining authorization or access blocker.
