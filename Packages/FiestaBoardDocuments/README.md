# FiestaBoardDocuments

Swift 6 / Foundation + CryptoKit document core. It preserves the complete page JSON tree across local name, template structure, and line formatting edits. It does not import FiestaBoardKit, communicate with a server, or publish to a board.

## Representation and edit policy

`PageDocument(data:)` requires a full raw page object. Do not reconstruct it from an API projection. The `root` retains unknown nested fields, canvases, geometry, transitions, explicit nulls, and all page types. `LosslessJSON.number(String)` preserves the original JSON numeric token without `Double` or `Decimal`. Serialization sorts object keys and normalizes whitespace/escapes; those syntactic details are not document content. String values and object keys compare exact decoded UTF-8 sequences, preserving canonically equivalent but scalar-distinct names such as U+00E9 and U+0065 U+0301. `LosslessJSONObject` backs `root` and `.object`, preserving String subscripts, dictionary literals, keys, iteration and filtering without native String-key normalization collisions. Invalid JSON, true duplicate decoded keys, invalid Unicode, and nesting beyond 256 levels are refused rather than silently repaired.

The archived backend stores template content as a string array plus `line_metadata`; the web editor translates that syntax to/from TipTap. It is not HTML. This slice exposes raw strings and leaves formatting/expression tokens untouched.

Template lines can be inserted, removed, moved, duplicated, and formatted with alignment/wrap. Structural operations move complete row records, including unknown metadata values and exact numeric spellings. Absent/null metadata stays absent/null through structure edits; explicit formatting materializes default metadata for all rows. Template editing requires type `template`, a string-only line array (including empty), no embedded line breaks, and absent/null metadata or a same-length array of metadata objects with supported known alignment/wrap values. Ambiguous content stays read-only. Name edits remain available independently of page content mode.

`changedFields(from:)` returns only changed top-level fields, including explicit null values. Field deletion throws: omission and null are not interchangeable. It is an inspection/future transport primitive, not server save authorization or concurrency protection.

## Local drafts and history

`DraftIdentity(deploymentID:pageID:)` must use immutable canonical deployment and page identities. Its equality and hashing use exact UTF-8 bytes, matching persisted identity validation without Unicode normalization. The actor `LocalDraftStore(directory:)` hashes a sorted, JSON-framed identity using SHA-256 for a traversal-safe filename. `defaultDirectory()` selects Application Support/FiestaBoard/LocalDrafts.

`save(_:)` validates both full raw documents and atomically replaces the latest draft file. A snapshot stores its baseline, current document, local revision, identity and timestamp. `load(_:)` distinguishes absence, recoverable draft, and corrupt/unsupported content; I/O errors propagate separately. A corrupt file cannot be overwritten. `quarantineCorruptDraft(_:)` explicitly preserves its original bytes under a unique filename, after which a new draft can be saved. No existing draft is automatically applied to fetched content.

`DocumentEditingSession` holds up to 100 undo versions in memory, each with its document and source baseline. Undo/redo advance local revisions. Recovery restores the saved draft's complete baseline and content, is undoable, and does not merge with a newer fetched page. Save checkpoints capture both document and baseline, so newer edits remain dirty after an asynchronous write. Only the latest explicit draft is persisted; undo history is not restored after process death. Share one store actor across editors; simultaneous editors are not a collaborative editing system.

## App integration

The native UI lives in `App/Features/Editor` and depends on this package:

```swift
let drafts = LocalDraftStore(directory: try LocalDraftStore.defaultDirectory())
let identity = DraftIdentity(deploymentID: canonicalDeploymentID, pageID: pageID)
let editor = try LocalPageEditorView(
    rawDocumentData: fetchedRawPageData,
    identity: identity,
    draftStore: drafts
)
// Present with a NavigationStack in a sheet or as a navigation destination.
```

Give each presentation a fresh identity/lifecycle; do not swap deployment/page parameters under an existing StateObject. The editor owns its Close action and dirty-dismiss protection. It labels Save as local draft only and makes no network calls. Raw line text uses a UIKit TextKit 1 representable with native marked-text input and selection. iOS compilation is checked; keyboard/IME/selection/undo behavior requires simulator/device UI verification before claiming parity.

Run host tests from the repository worktree:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" swift test --package-path Packages/FiestaBoardDocuments --disable-sandbox --scratch-path .build/editor-docs
```
