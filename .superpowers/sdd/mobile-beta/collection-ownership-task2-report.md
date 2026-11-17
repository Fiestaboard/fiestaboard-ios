# Collection ownership Task2 implementation report

Status: source implementation and focused verification complete; independent review and controller native acceptance pending. Task1 passed independent review and its integrated unsigned device build before this work began.

## Review range and ownership

- Product commit: `49070b439f8719409e6153703bd0b648975ee32a`.
- Exact source review range: `4ffe16456a02eb239da5d5ee2d5aa1d2aa665e75..49070b439f8719409e6153703bd0b648975ee32a` (10 owned files).
- Active repository: `/Users/jeffre/workspace/fiestaboard-ios-beta-recovered-20261031`; frozen original Documents checkout untouched.
- Owned existing files: `CollectionDraft.swift`, `LocalPageEditorLoader.swift` recovery destination, and the minimal `CollectionDraftResources` visibility change in `CollectionsView.swift`.
- New focused files: `CollectionRecoveryTests.swift`, `CollectionRecoveryUITests.swift`, and `Tests/Fixtures/CollectionRecovery/{manifest.json,setup.md,originals/*}`.
- Existing `DemoUITests.swift`, flexible editor product files, generated project and controller aggregate/diagnostic docs were not edited or staged. No subagents, simulator commands, software/security changes, physical devices, production actions or publication.

## Behavior and interfaces

`CollectionDraftRecoveryEntry` uses its original file URL as stable identity and carries an optional safely decoded checkpoint, a typed human-readable classification and reason. `CollectionDraftArchive.recoveryInventory()` discovers original local files without creating directories, changing archives, adopting content or writing retirement markers. Retirement metadata is explicitly excluded. Original retired JSON files remain listed for export. Unsupported format versions are classified before typed decoding and never exposed as validated scoped checkpoints. Filename/checkpoint UUID mismatch or malformed/inconsistent scoped identity is untrusted, with no checkpoint installed. Invalid bytes and I/O failures remain explicit inspectable entries. An unreadable store directory throws so the UI can report that store's failure separately.

The existing connected/disconnected recovery destination now has standard Pages and Collections sections. Page details/export behavior is preserved. Collection rows show a safe saved name or ID/new-collection fallback, classification and original filename. Details show historical scope/status/revision, preserved numeric text and source read-only evidence when safely available. They explicitly avoid claiming ownership by the current sign-in. A leaf ShareLink exports the entry's original URL; no JSON reconstruction, recovery/adoption button or mutation action exists in this inventory. Page and collection load errors are caught independently; the global empty state requires both successful inventories to be empty. Both editors and inventory share the existing `CollectionDraftResources.archive`.

Task1 active recovery and exact-identity/version lineage gates are unchanged. No collection protocol expansion, raw document parity, schedules or sync framework is included.

## Regression evidence

Evidence directory: `/Users/jeffre/workspace/mobile-beta-discovery/evidence/collection-ownership-task2/`; matching originals remain in `/tmp`.

- `fb-collection-recovery-red.log`: tests written before the inventory API; expected missing-interface compile failure. It also contains an early optional-checkpoint assertion requiring Equatable, corrected to `XCTAssertNil`. This is compilation evidence, not claimed behavioral red evidence.
- `fb-collection-recovery-first-run.log`: first implemented focused run,4 tests with1 failure. The unreadable-file assertion compared `/var/...` against Foundation's discovered `/private/var/...` alias. The test now compares resolved URLs for that alias-sensitive case; production keeps the actual discovered file URL. This was a fixture/path expectation correction, not a weakened byte-identity assertion.
- Final `CollectionRecoveryTests`:6/6 pass. Tests cover all five requested archive classes including retired originals, unchanged original and marker bytes, exact discovered URL identity, future/invalid scope/filename mismatch classification, unreadable file entries, missing stores without creation, store enumeration errors, preserved unsupported-baseline read-only evidence and revision, and checked-in fixture hashes/classifications/export bytes. Existing Task1 ownership/model tests remain green.
- Standalone native typecheck initially omitted the installed XCTest Swift overlay search path, yielding unavailable Swift assertion functions. `fb-collection-task2-ui-typecheck-initial.log` preserves it. Adding the installed platform `Developer/usr/lib` search path fixed the command without product changes. Final typecheck uses project Swift6 mode and exits0.

## Native journeys prepared for controller acceptance

`CollectionRecoveryUITests/testSameScopeCreationDraftRecoversExactNativeInputAfterRelaunch` uses the existing demo verified scope. It opens a new collection, types a unique name and a decimal point into the interval, captures the exact invalid value, keeps the draft, terminates/relaunches, explicitly selects its recovery entry and verifies the same name and exact interval. Save must remain disabled. It explicitly discards only this recovered test lineage and checks that entry is no longer offered. No app seeding substitutes for this input/recovery interaction and no collection save is sent. The decimal intermediate is invalid regardless of native caret placement; it avoids the parseable `-30` case identified during controller pre-runtime review.

`CollectionRecoveryUITests/testOriginalCollectionInventoryAndShareSheetConnectedThenDisconnected` requires the controller-seeded exact fixture files and test-runner `COLLECTION_RECOVERY_SEEDED=1`. It verifies each legacy/future/malformed filename and classification from both connected and disconnected routes, checks the absence of recovery/adoption/save actions, opens the normal system share sheet, and dismisses it without choosing an activity or recipient. The flag does not seed product state; absent setup explicitly skips. App inventory/details screenshots are attached, **never share-sheet screenshots** because the system may suggest personal recipients.

Controller setup is checked in at `Tests/Fixtures/CollectionRecovery/setup.md`. Copy only the three `originals/` files to the task simulator app's `Library/Application Support/FiestaBoard/CollectionDrafts`, preserving unrelated drafts; verify hashes before/after. Manifest/setup stay outside the app's draft directory. Controller owns project regeneration, immutable archived build, simulator seeding/runs, screenshot delivery and cleanup. No runtime or screenshot success is claimed from static checks.

## Exact synthetic originals

All values are synthetic, with a non-routable `.invalid` deployment and dedicated UUIDs.

| Filename suffix | Bytes | SHA-256 | Expected classification |
| --- | --- | --- | --- |
| `000201.json` |562|`1a02bfe13e92951561cae0ba977a676c0ab805953d38aac7a2808661b2c01c4b`|Unassigned legacy draft|
| `000202.json` |872|`d19fa33bc61c20fed0b77cf8f6feede73e5d486e7329382e7d68e53450a8d79c`|Unsupported archive format|
| `000203.json` |35|`bd75500759df73982ae361ffd03db34dbb9c1c7d3749808ebbd561014ffaed1a`|Damaged draft|

Full filenames, deployment, container-relative location and expectations are pinned in the checked-in manifest and verified by XCTest. The future file includes opaque Unicode/newline data; the damaged file intentionally has non-UTF-8 bytes.

## Final commands and results

From the active repository:

```sh
SWIFT_MODULECACHE_PATH=/tmp/fb-collection-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-collection-clang-cache swift test --disable-sandbox --package-path Packages/FiestaBoardEditorState --scratch-path /tmp/fb-collection-editor
swiftc -parse App/Features/Library/LocalPageEditorLoader.swift App/Features/Collections/CollectionsView.swift Tests/UITests/CollectionRecoveryUITests.swift
```

Full EditorState: exit0,83 tests,0 failures, including6 new focused recovery tests; completion directly observed for session65733. Evidence: `fb-collection-task2-editor.log` and `.exit`.

Focused standalone native test typecheck (no build/link or simulator action):

```sh
task_sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
task_developer_path=$(xcode-select -p)
SWIFT_MODULECACHE_PATH=/tmp/fb-collection-ui-module-cache CLANG_MODULE_CACHE_PATH=/tmp/fb-collection-ui-clang-cache xcrun swiftc -typecheck -swift-version 6 -target arm64-apple-ios26.0-simulator -sdk "$task_sdk_path" -F "$task_developer_path/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks" -I "$task_developer_path/Platforms/iPhoneSimulator.platform/Developer/usr/lib" Tests/UITests/CollectionRecoveryUITests.swift
```

Typecheck, final app/test parse and owned-path `git diff --check`: exit0. Evidence: `fb-collection-task2-ui-typecheck.log`, `.exit`, `fb-collection-task2-parse.log`, `.exit`. Kit/AppState/Python suites were not repeated because Task2 changes only archive inspection and native recovery; their Task1 full verification remains recorded separately. New sources require controller-owned project regeneration before integrated native compilation.

## Remaining acceptance

Independent Astra source review and controller actual phone/tablet build/tests/screenshots are pending. Native accessibility/share-sheet selectors require actual runtime verification; no UI success is inferred from typechecking. No filesystem, permission or uncertain process/mutation blocker remains. All original checkpoint bytes remain retained, including retired versions.
