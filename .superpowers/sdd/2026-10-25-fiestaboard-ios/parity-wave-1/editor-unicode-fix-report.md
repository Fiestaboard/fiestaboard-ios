# E-01 Unicode review correction

Corrects the confirmed P2 in `astra-review.md` against candidate `ec55acf`. Owned source changes remain inside `Packages/FiestaBoardDocuments` and `App/Features/Editor`; no AppRoot, project, controls, signing or main-checkout files changed by this owner. No new production source files were added, so project generation needs no new file entry.

## Root cause and correction

Swift `String` equality/hash use canonical Unicode equivalence. JSON/Python raw template variables and keys distinguish decoded Unicode scalar sequences. Synthesized `LosslessJSON` equality therefore discarded an edit from U+00E9 to U+0065 U+0301, and native `[String: LosslessJSON]` could not retain both distinct keys. The same equality weakened persisted `DraftIdentity` validation, and two UIKit comparisons could suppress scalar-distinct text synchronization.

`LosslessJSON` now compares string values and numeric lexemes using decoded UTF-8 byte equality, recursively through arrays and objects. UTF-8 is a unique encoding of valid decoded scalar sequences, so escaped and literal spellings of the same scalar sequence remain equal without normalizing different sequences. `LosslessJSON.stringsEqual(_:_:)` supplies the same comparison to the UIKit representable.

New `LosslessJSONObject`, declared in the existing `LosslessJSON.swift`, stores a dictionary keyed by an exact UTF-8 hash/equality wrapper. It retains separate canonically equivalent keys, rejects true duplicate decoded scalar keys, and serializes in deterministic exact UTF-8 key order. It preserves dictionary literals, String subscripts, `keys`, count/emptiness, iteration and filtering. The necessary public type change is `.object(LosslessJSONObject)` and `PageDocument.root: LosslessJSONObject`, replacing native String-key dictionaries. Existing app integrations consume projections and require no call-site change; current literal/subscript/patch APIs compile unchanged.

Document/checkpoint/history equality and `changedFields(from:)` inherit the exact recursive comparison. DraftIdentity now explicitly hashes and compares the UTF-8 sequence of each immutable component. Filenames continue to hash the existing JSON-framed exact identity, and a canonically equivalent but scalar-distinct identity in a stored envelope is now rejected. Both raw-text UIKit equality checks now use `LosslessJSON.stringsEqual`; marked-text and selection policy is otherwise unchanged.

## Red/green evidence

Eight new meaningful package tests cover:

- Actual raw-template normalization edit surviving adoption, revision increment, dirty state, undo/redo, metadata preservation, changed-field patch and serialized scalar round trip.
- Name normalization edit, changed-field patch, save checkpoint and dirty undo.
- Separate nested scalar-distinct keys through parsing, edits, exact lookup and serialization.
- Escaped/literal true duplicate rejection while escaped/literal identical scalar strings remain equal.
- Dictionary literal/mutation/removal and changed-field filtering preserving separate exact keys.
- Distinct-key rename requiring the existing explicit deletion policy.
- DraftIdentity equality/hash collections distinguishing each identity component.
- Persisted wrong-identity envelope rejection for canonically equivalent deployment and page IDs, with filename separation retained.

Before production changes, the initial seven tests ran and failed with 23 assertions/errors, including the review's actual edit drop and false duplicate rejection (`editor-unicode-red.log`). The eighth test adds direct public literal/subscript/patch verification. Full final host suite passed **22 tests, zero failures** (`editor-unicode-tests.log`). Only known inaccessible user-cache/read-only manifest-cache environment warnings remain; no source warnings.

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" swift test --package-path Packages/FiestaBoardDocuments --disable-sandbox --scratch-path .build/editor-docs
```

Fresh Swift6/iOS17 arm64 simulator module compilation and editor typecheck each exited **0**, no diagnostics (`editor-unicode-ios-build.log`, `editor-unicode-ios-typecheck.log`):

```sh
xcrun swiftc -emit-module -parse-as-library -swift-version 6 -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.1.sdk -module-cache-path .build/clang -module-name FiestaBoardDocuments -emit-module-path .build/editor-ios/FiestaBoardDocuments.swiftmodule Packages/FiestaBoardDocuments/Sources/FiestaBoardDocuments/*.swift
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.1.sdk -module-cache-path .build/clang -I .build/editor-ios App/Features/Editor/*.swift
```

A bounded Jev representation decision was attempted once, but the tool rejected four requirements because its runtime maximum is three. It returned no decision/advice and no recommendation was claimed. No retry, Opus call, CLI authentication change, or additional agent was used. The representation was selected through source inspection and verified by tests.

## Remaining gates

This correction closes exact-Unicode codec/model/identity comparisons and the identified UIKit comparison defect. It does not claim runtime UI/IME/selection parity. The prior TextKit device/simulator interaction test gate, integrated app builds/review, raw-only fixed-slot scope, local-only draft behavior, and lack of remote writes remain. Root/integrator owns the final combined native builds and independent Astra recheck.
