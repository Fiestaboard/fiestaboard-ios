# E-01 document and local editor report

Implemented in the foundation worktree only. Owned paths: `Packages/FiestaBoardDocuments/**`, `App/Features/Editor/**`. No project/AppRoot/main-checkout/signing files changed by this owner. Root integrates the view and local package.

## Actual Claude CLI result

Invoked installed Claude Code 2.1.292 for meaningful bounded document codec/tests implementation, using prompt file `editor-opus-prompt.txt` in this directory:

```sh
claude -p --model opus --no-session-persistence --safe-mode --strict-mcp-config --disable-slash-commands --tools 'Read,Glob,Grep,Write,Edit,Bash' --allowedTools 'Read,Glob,Grep,Write(Packages/FiestaBoardDocuments/**),Edit(Packages/FiestaBoardDocuments/**),Bash(swift test *),Bash(env CLANG_MODULE_CACHE_PATH=*)' --max-budget-usd 12 --output-format json < .superpowers/sdd/2026-10-25-fiestaboard-ios/parity-wave-1/editor-opus-prompt.txt > .superpowers/sdd/2026-10-25-fiestaboard-ios/parity-wave-1/editor-opus-result.json
```

Normal permissions; no bypass, configuration/credential changes, external MCPs, or helper agents. The CLI returned before implementation: `is_error: true`, HTTP 401, one turn, duration 2427 ms, `modelUsage: {}`, no permission denials. Exact error: **“Failed to authenticate. API Error: 401 OAuth access token has expired. Re-authenticate to continue.”** The full result remains in `editor-opus-result.json` locally. Parent was notified promptly; no retry of the unchanged auth failure. **Opus made no contribution. Sol implemented and verified all delivered files.**

## Delivered behavior and integration APIs

`FiestaBoardDocuments` is a Swift 6 package using Foundation/CryptoKit, with no Kit/service/network dependency. `LosslessJSON` retains recursive unknown nodes and arbitrary-precision numeric lexemes as strings, distinguishes missing/null, validates strict JSON/Unicode and refuses duplicate keys. Serialization canonicalizes key order/whitespace/escapes without converting number tokens. A full object is required by `PageDocument(data:)`; never encode a lossy page projection as input.

The source contract was checked against archived `src/pages/models.py`, `web/src/lib/api/pages.ts`, `web/src/components/page-builder.tsx` loading code, and `web/src/components/tiptap-template-editor/utils/serialization.ts`. Raw templates are string arrays with separate line metadata; they are not HTML. All page types, canvases, geometry, transitions and future nodes remain in the raw tree.

`PageDocument` exposes `name`, `pageType`, `templateLines`, `editableTemplateLines`, read-only `root`, `setName(_:)`, `replaceTemplateLine(at:with:)`, `serializedData()`, and `changedFields(from:)`. Changed-field patches contain only modified fields and preserve explicit nulls; implicit field deletion throws. Name validation matches the backend's 1...100 Unicode-code-point length bounds. Templates are editable only when their shape and optional metadata safely support it. Unknown metadata fields survive. **Original array index is line identity; structural line edits are explicitly blocked.** No insert/delete/reorder/split/merge, metadata synthesis or rich-content conversion occurs.

`DraftIdentity(deploymentID: String, pageID: String)` is immutable Codable/Hashable/Sendable. Supply the canonical immutable deployment identity, not a display name or credential. JSON framing plus CryptoKit SHA-256 gives stable traversal-safe filenames. `LocalDraftStore(directory: URL)` is an actor; `defaultDirectory() throws -> URL` selects Application Support/FiestaBoard/LocalDrafts. Share one store across editor presentations.

`DraftSnapshot` contains schema version, immutable identity, full raw baseline/current documents, local revision and timestamp. `save(_:)` validates both documents and atomically replaces the file. `load(_:)` returns `.absent`, `.recovered(snapshot)`, or `.corrupt(issue)`; I/O errors propagate. Corrupt/unsupported files remain untouched and block save until explicit `quarantineCorruptDraft(_:)` preserves their bytes separately. The view exposes that recovery action. Latest explicit snapshot persists; 100-version undo/redo history remains in memory. Local revisions make no server concurrency claim.

`DocumentEditingSession` validates copies before mutation, tracks dirty state/checkpoints, advances revisions on effective edits/undo/redo, and recovers complete baseline+document only after explicit user choice. History restores both content and source baseline. Saving a captured document does not clear newer edits.

App integration is a throwing MainActor initializer:

```swift
let drafts = LocalDraftStore(directory: try LocalDraftStore.defaultDirectory())
let identity = DraftIdentity(deploymentID: canonicalDeploymentID, pageID: pageID)
let editor = try LocalPageEditorView(
    rawDocumentData: fetchedRawPageData,
    identity: identity,
    draftStore: drafts
)
```

Present inside a NavigationStack with a fresh presentation identity/lifecycle. Do not replace deployment/page under an existing StateObject. The view offers name/raw fixed-slot template editing, selectable read-only raw JSON for unsupported content modes, explicit local draft recovery/save, undo/redo, close confirmation and interactive-dismiss protection. Labels consistently say local draft, never server Save. TextKit 1 `UITextView` storage/layout supports native selection and marked-text entry without markup rewriting. Text input is committed before explicit close/save/history actions. Save-and-close refuses to dismiss if newer edits remain.

## Verification evidence

Tests were written before their corresponding production code. Initial codec and draft red logs show missing requested APIs; both subsequent recovery/baseline edge regressions were observed failing assertions before fixes (`editor-recovery-red.log`, `editor-baseline-red.log`).

Full host package suite command:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" swift test --package-path Packages/FiestaBoardDocuments --disable-sandbox --scratch-path .build/editor-docs
```

Final result: **14 XCTest tests, zero failures**, 2026-10-25 23:21:20 (test log timestamp) (`editor-tests.log`). Coverage includes deep unknown/canvas preservation, huge integer/precise decimal/exponent tokens, explicit-null versus omission across known/future page types, invalid numbers/UTF-8/surrogates/duplicate keys, metadata-safe fixed-slot edits, unsupported edit refusal/atomicity, changed-only patches/deletion refusal, undo/redo branching and save checkpoints, explicit recovery baseline/history, actor persistence and deployment isolation, corruption preservation/quarantine, identity mismatch and invalid embedded documents. SwiftPM emitted only environment warnings for inaccessible user-level caches and a read-only manifest cache; tests ran using workspace scratch/module paths.

Fresh iOS17 arm64 simulator module compilation and editor typecheck both exited **0**, with no diagnostics (`editor-ios-build.log`, `editor-ios-typecheck.log`):

```sh
xcrun swiftc -emit-module -parse-as-library -swift-version 6 -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.1.sdk -module-cache-path .build/clang -module-name FiestaBoardDocuments -emit-module-path .build/editor-ios/FiestaBoardDocuments.swiftmodule Packages/FiestaBoardDocuments/Sources/FiestaBoardDocuments/*.swift
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.1.sdk -module-cache-path .build/clang -I .build/editor-ios App/Features/Editor/*.swift
```

The first UI typecheck exposed SDK27's macro overload for `@State` and a throwing `StateObject` autoclosure. Both were corrected with an explicit property-wrapper alias and preconstructed throwing model. No @Observable or preview macros are used. No device/automated UI test, production server/hardware call, or rich editor parity claim is made. Root owns integrated application build and the full cross-package suite.

## Limitations and exact next gates

This is a local raw editor foundation, not full rich-editor parity. Structural template editing, geometry/canvas/transition controls, previews/renderer, token UI, durable undo history, and server save are absent. Draft writes are explicit; unsaved content is not autosaved across process termination. Multiple simultaneous editor sessions use the last explicit local write; this is not collaborative editing. JSON nesting beyond 256 and ambiguous/duplicate keys are rejected instead of repaired.

Before calling TextKit editing complete: run simulator/device UI tests for selection ranges, non-BMP text, marked-text/IME commit/cancel, paste/newline refusal, native versus document undo, focus changes, and close/drag/back dismissal. Before rich conversion: define a token-aware AST/line identity model from the archived serializer, validate all markup/unknown-node round trips, establish explicit split/merge/insert/delete metadata rules, and pass those TextKit interaction tests. Before server writes: establish real backend revision/ETag capability or an explicit conflict protocol, retain/recheck the exact raw fetched baseline, send only reviewed changed-field patches with supported deletion semantics, and test remote-change conflicts/recovery. Local revision counters must never be advertised as conditional server writes.
