# Native draft verification

The user requested continued implementation through a draft they could test. This delivers a bounded development draft from milestones 1, 2 and 3A. Full web-app parity remains the release requirement; the remaining protocol work and product milestones are still open.

## Delivered

- Universal SwiftUI app for iOS/iPadOS 26+, built with Xcode 27.1 / SDK 27.1. Native adaptive tabs/sidebar and toolbars provide system Liquid Glass; layout follows container geometry.
- Home, searchable read-only Library, Displays and Settings; manual connection/sign-in, explicit local HTTP choice, per-deployment memory sessions, and a 6×22 simulated demo.
- Server-reported and expected frames, selected/resolved/scheduled page distinctions, captured-target text/page confirmations, and distinct accepted/held/partial/rejected/unknown outcomes.
- Swift core and app-state packages, Xcode project/shared scheme, unsigned build script, bundled demo data and attribution, privacy manifest, and [run/test instructions](../draft-testing.md).

Sol 6.1 implemented the core and app. Astra independently reviewed both tasks and the app/core integration. No production board commands were sent. Root made read-only shape probes against the existing 9.14.9 server; these were not end-to-end native app tests.

## Verification

| Check | Result |
| --- | --- |
| FiestaBoardKit host tests | 23 passed |
| App state and flap mapping host tests | 15 passed |
| Existing contract-tool tests | 25 passed |
| Contract integrity | Passed; explicitly not release ready |
| Unsigned Simulator app | Build passed, arm64 and x86_64 |
| Unsigned device app | Build passed, arm64 |
| UI test bundle | Build-for-testing passed; tests not executed |
| App packaging | Both frameworks, six demo fixtures, attribution and privacy manifest present |

The build and test commands are in the testing guide. The app artifacts are under `.build/draft-derived/Build/Products/Debug-iphonesimulator/FiestaBoard.app` and `Debug-iphoneos/FiestaBoard.app` in the implementation worktree. Device installation still requires the user's signing team; no signing credentials are committed.

The environment denied CoreSimulatorService access and Xcode UI control. No simulator launch, screenshots, interactive visual review, UI test execution or physical-device verification is claimed. Runtime resizing, Duo poses, keyboard, VoiceOver, Dynamic Type and appearance checks remain in the manual matrix. Existing cache/CoreSimulator/AppIntents warnings did not prevent the successful builds.

## Review corrections

Core review approved `26fd5d9` after replacing textual IPv6 prefix checks with parsed address-range checks and adding regressions. This prevents nonlocal addresses such as `fc::1` from entering the local HTTP exception.

Integrated app review identified stale UI permissions after authentication expiry and silent server-logout failure. Commit `d6b8a26` centralizes authentication-loss handling, invalidates old confirmations, preserves an acknowledged send when subsequent readback requires sign-in, and reports pending/confirmed/unconfirmed logout without overwriting a newer connection. Five additional host cases cover these paths; the failing cases were observed before the fix.

Astra's scoped recheck approved the bounded testable draft at `d6b8a26` for spec compliance and code quality, with no remaining material findings. An independent offline probe confirmed the corrected authentication and logout behavior. This is not runtime visual validation or release approval.

## Deliberate draft limits

Unknown and 9.x servers are read-only. Live controls require an explicit opt-in on exact non-development 10.0.0; that is a draft schema gate, not release support. Sessions are memory-only, refresh is manual, pages are read-only, and the renderer supports bounded split-flap grids. Discovery, setup, OAuth, editors, revision-aware saves, scheduling controls, integrations/admin, complete pixel rendering, localization and release assets remain future work.

Xcode compiles the same package sources as native framework targets because its SwiftPM manifest cache was inaccessible here. Standard Combine observation and an explicit alias to the SwiftUI State property wrapper avoid unavailable compiler-macro execution. SwiftPM remains available for host tests. These are reversible build adaptations; no global permissions or compiler sandbox controls were changed.
