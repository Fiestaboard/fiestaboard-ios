# Setup and current controls — October 28 quality checkpoint

Later page implementation and iPhone performance findings are recorded in [the page lifecycle checkpoint](2026-10-28-native-page-lifecycle-verification.md); its results supersede pending items in this earlier snapshot.

This is a testable draft milestone, not full web parity or release acceptance. User priority: setup/sign-in, board switching and page management, settings, then native rich editing for **both split-flap and LED**.

## Changes accepted

- `3e5f031`: setup recovery preserves authenticated cookies; preferred-board restoration retains ambiguous-command barriers; windows share one saved-server writer while active sessions remain scene-local. Astra round-one recheck accepted all three corrections.
- `2722652`: additive exact10.1.20 source evidence,72 control cases and57 bootstrap cases. Astra accepted bounded candidate compatibility; provider/cache changes are not covered.
- `6c64271`, `81b0fb8`: current17/20 controls and concrete-board, original-revision fallback updates. Prepared actions cannot silently replace revisions, retry ambiguous writes or bypass a missing conditional context. Explicit Demo/legacy capabilities retain their previous behavior. Astra accepted the correction.
- `be85cfa`: clearer native welcome/focus behavior, accurate compatibility copy, live project source registration, actual onboarding UI scenarios, signed Simulator Keychain testing and adaptive confirmation handling.
- `b7c2e00`:48 additive page create/delete source records accepted by Astra for the next native slice. Native create/delete implementation is still pending.

Fresh integration Astra review found no new Critical, Important or Minor source findings. Its scope does not infer device or full-parity acceptance from compilation.

## Verification evidence

| Check | Actual result |
| --- | --- |
| Kit / AppState |124 /76 tests passed after control review correction |
| Contract tooling / project tooling |56 /15 tests passed |
| Project generation / workflow syntax |Project and schemes match; actionlint passed |
| Current manifests |10.1.20 verifier2 tests passed; page48-record artifact/source verifier passed |
| Source-handler replay |Current20 bootstrap/control3 tests passed; page-management2 tests passed (positive and deliberately altered-receipt rejection) |
| Unsigned iPhone SDK build |Passed with the integrated current source |
| iPhone Simulator27.0 |All11 scenarios passed across a full run with10 passes and one test-input failure, followed by the corrected remaining scenario passing. This is not a single all-green full-suite run. |
| iPad Simulator |Original runtime failed to launch the test runner after a system-shell crash; fresh temporary iPad run pending at this checkpoint. No tablet pass is inferred. |
| Live server API |Temporary authenticated API session confirmed10.1.20 nondevelopment,4 boards,40 pages; logged out afterward. No physical/content/settings writes. |
| Actual native phone/live Keychain/LAN |Still requires device walkthrough; standalone macOS URLSession and Python networking were denied even though curl could reach the server. |

The three new native onboarding scenarios exercise actual UI and URLSession with a loopback-only synthetic fixture: first-run authentication choice/administrator creation/library loading, no-auth setup at accessibility XXXL, and wrong-password recovery/rotation/Keychain-backed remembered session across process relaunch/logout. Every completed scenario removes its own saved server. The fixture identifies itself as an audited nondevelopment version, so initial disabled controls genuinely test absence of automatic write opt-in. It provides no display/content mutation endpoints.

The eight Demo scenarios cover navigation/composition, confirmation cancellation/pause, unknown-outcome recovery, paused restore refusal, local draft retention/discard, page preview/confirmed save and conflict comparison/reload. Native confirmation popovers omit visible cancel actions in some layouts; tests now dismiss outside and verify unchanged pending state. A text-field input test now scrolls its center below the navigation bar before tapping.

Unsigned Simulator apps failed Keychain access with securityd error-34018 (missing application/keychain entitlements). Local ad-hoc signing resolved the runtime problem; no in-memory vault substitution was used. Apple's strong-password suggestion remains enabled in the app and is handled explicitly by setup automation. A disk-full incident interrupted the first combined device run;23 obsolete ignored SwiftPM scratch caches were removed, retaining source, credentials, user files and test logs.

Detailed local evidence lives in `.superpowers/sdd/2026-10-28-native-parity-completion/` and `/tmp/native-*.log`; raw XCTest bundles are under `.build/runtime-derived/Logs/Test` and `.build/runtime-ipad/Logs/Test`. Hosted CI has not run; the definition now starts its local fixture, signs UI builds locally and checks both additive fixture manifests.

## Remaining user-facing scope

Main integration preserves all existing signing/project settings. After installation, open the normal **FiestaBoard** scheme, connect to your local server and sign in. Choose a board; changes stay disabled until explicitly enabled in Settings. Confirm the intended board before any send. A server acknowledgement is not independent physical observation.

Next implementation is native page creation and original-revision deletion/library refresh, following the committed page-management gap audit. Rich editing, complete settings/admin, full rendering and remaining84-workflow parity are still tracked in TASKS.md and the master checklist.
