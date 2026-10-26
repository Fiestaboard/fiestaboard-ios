# W1-03 native integration

## Scope

- Added Home → Board controls navigation to a Form containing the control owner's Section; existing read-only/write-gate and per-action captured-target confirmations remain active.
- Added exhaustive configuration/restore descriptions to the root action-review switch.
- Moved page detail into Library and added **Edit local draft**. The sheet loads a full raw page snapshot through `BoardStore.loadPageDocument`, captures its canonical deployment/page identity, and constructs one local editor per sheet presentation. Geometry changes do not reload it.
- Connection loss or connection-label changes dismiss the editor. Cancelled or stale document loads cannot present a new editor. A shared file actor serializes local draft operations across windows.
- Added the native FiestaBoardDocuments framework target from the same source files used by the independently host-testable package. Demo fixtures remain assigned to FiestaBoardKit.
- Updated draft scope and demo copy to distinguish simulated board actions from real on-device draft persistence. Added UI test source for local editor entry/unsaved-close confirmation and board-control cancellation/confirmed pause.

## Validation

Validated the combined sources after controls commit `0448589` and editor commit `05f4e35`.

| Command/check | Result | Evidence |
| --- | --- | --- |
| `xcodegen generate` | Exit 0; project regenerated in foundation worktree | `integration-xcodegen.log` |
| `scripts/build-draft.sh simulator` | Exit 0; `BUILD SUCCEEDED` | `integration-simulator.log` |
| `scripts/build-draft.sh device` | Exit 0; `BUILD SUCCEEDED` | `integration-device.log` |
| `xcodebuild -project FiestaBoard.xcodeproj -scheme FiestaBoard -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.build/draft-derived" CODE_SIGNING_ALLOWED=NO build-for-testing` | Exit 0; `TEST BUILD SUCCEEDED` | Initial `integration-uitest-compile.log`; final `integration-uitest-compile-mainactor.log` |
| Product inspection with Python pathlib assertions | Both app products embed FiestaBoardKit, FiestaBoardAppState and FiestaBoardDocuments binaries; both retain all six demo JSON fixtures in Kit | Artifact assertions printed for Debug-iphonesimulator and Debug-iphoneos |
| `git diff --check` | Exit 0 | No whitespace errors |

The initial test compilation exposed repeated warnings from one cause: UI test methods called XCTest's MainActor APIs from nonisolated methods. Added `@MainActor` to all three UI test methods and reran build-for-testing. The final log contains no Swift source warnings; AppIntents metadata-extraction notices and inaccessible CoreSimulator service diagnostics remain environmental. No tests were executed as part of build-for-testing. Package host-test evidence belongs to the component owner reports and was not duplicated here.

The generated project retains `CODE_SIGN_STYLE = Automatic` and blank `DEVELOPMENT_TEAM` defaults. Its changes add the new native framework and App feature source memberships; no main-worktree signing selections were overwritten.

## Limits

No signing configuration on main was touched. Builds use `CODE_SIGNING_ALLOWED=NO`. No live server, hardware, simulator execution, UI test execution or visual QA is claimed. UI source targets an iPhone-sized navigation surface. Runtime checks remain necessary for rotation/iPad widths, keyboard/IME, accessibility, local recovery and connection-loss dismissal. This wave supplies bounded local drafts and board controls; it does not deliver full web parity, server page publishing, schedule editing, plugins, administration or pixel rendering.
