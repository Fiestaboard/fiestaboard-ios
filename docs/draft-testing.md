# Native draft testing

This is a runnable iOS/iPadOS 26+ SwiftUI draft built with Xcode 27.1 / SDK 27.1 and Swift 6. It covers demo mode, manual server connection, display selection, server-reported output, a read-only page library, and basic text/page controls. It is not full web parity or a supported released server/app pairing.

## Open and run

From the repository root:

```sh
open FiestaBoard.xcodeproj
```

Select the shared **FiestaBoard** scheme, choose an installed iPhone or iPad simulator, and press Run. The scheme includes `--demo`, which creates a memory-only demo without a network session. Remove `--demo` under Product → Scheme → Edit Scheme → Run → Arguments to see Welcome and enter a server. The app never restores or automatically connects to a live deployment on launch.

The generated project is committed; XcodeGen is only needed to regenerate it after changing `project.yml`:

```sh
xcodegen generate
scripts/build-draft.sh simulator
# Optional unsigned physical-device SDK build, not installable without signing:
scripts/build-draft.sh device
```

Build artifacts are `.build/draft-derived/Build/Products/Debug-iphonesimulator/FiestaBoard.app` and, if requested, `Debug-iphoneos/FiestaBoard.app`. Use Xcode and your own signing team to run on a device; no development team or signing credential is committed. There is intentionally no asset catalog or app icon in this draft.

## Demo walkthrough

1. Tap **Explore Demo**, or launch the shared scheme with `--demo`.
2. Home shows **Demo Kitchen**, its server-reported output, selected/resolved/scheduled page distinctions, and a simulated connection banner.
3. Compose text, enter `HELLO`, then **Review action**. Confirm the captured server, board ID and exact text; **Confirm simulated action** changes only memory. The result says whether a send was acknowledged and never claims physical observation.
4. Open Library, search `Sunny`, open **Sunny day**, and simulate showing it on the selected board. Template source is read-only; expressions/plugins are not rendered.
5. Open Displays and use **Demo Pixel Panel**. Its unsupported character set is explained rather than displayed as a flap approximation. Switch back to Demo Kitchen.
6. In Settings, choose a simulated outcome: accepted, held, partial, rejected or unknown. Held selection remains distinct from reported output. Partial and unknown results require **Refresh output** before another action. Refresh reads state and never replays a mutation.
7. Disconnect. A new demo starts from the bundled fixtures.

Demo Kitchen uses a 6 × 22 split-flap welcome frame with color cells. Simulated text wrapping is simpler than backend layout. All demo controls are labeled simulated. The split-flap table is reused from the TV project under its [MIT license](../ThirdPartyNotices/FiestaBoardTV-MIT.txt); this app does not claim TV renderer parity.

## Connect to your server

Remove `--demo` from the scheme and use **Manual server connection**. Enter the deployment root with scheme, port and any reverse-proxy prefix, for example `https://board.example.com/fiesta`. Do not append `/api`; the app adds `/api` after the deployment prefix. URL credentials, query strings, fragments, path traversal and percent-escaped prefixes are refused.

HTTPS uses normal system trust and is required for public hosts. For a local HTTP server, explicitly enable **Allow HTTP on my local network** and enter a permitted local address such as `http://fiestaboard.local:5000`. The app declares a local-network purpose and allows local networking only; it has no arbitrary-load ATS exemption. On a phone, `localhost` refers to that phone, not your Mac. Use the server’s LAN address and grant the system local-network prompt when appropriate. No Bonjour discovery, server setup or OAuth flow is implemented.

Enter username/password if the server requires login. Passwords are removed from the form immediately after starting an attempt and are never persisted. Cookies use an isolated, ephemeral, memory-only session scoped to the complete deployment identity, including port and proxy prefix. Each app window owns a separate store/session. **Disconnect** drops the local session; **Log out & disconnect** also attempts to revoke the old server session. Welcome shows whether that sign-out is pending, confirmed or could not be confirmed; failed sign-out may leave the server session active. A late result from the old server does not replace a newer connection. If any read or action discovers expired authentication, the app disables controls and returns to the connection form to sign in again. An acknowledged send remains acknowledged if its later readback loses authentication, and is never replayed. No session restoration or Keychain storage is implemented.

Every new manual connection starts read-only. Settings → **Draft controls** exposes an explicit **Enable controls on this server** opt-in and **Apply control setting**. The underlying candidate gate permits only an exact non-development `running_version` of `10.0.0`. Unknown versions and all 9.x servers, including the observed 9.14.9 read-shape server, remain read-only even with opt-in. The version string is a draft schema gate, not proof of backend commit identity or release support. These controls may change the chosen physical board; review the captured deployment, board and content before confirming.

No automated test connects to a live server or hardware. A successful send receipt means server acknowledgement, not physically verified output. Reported frames may be cached. Readback failure, partial writes and unknown outcomes remain visible; there are no automatic retries or mutation replay. Commands are serialized per immutable target, including when switching away and back. A cancelled or stale command result requires fresh readback before reusing that target.

## Verification

Host tests use local caches:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" \
  swift test --package-path Packages/FiestaBoardKit --disable-sandbox --scratch-path .build/draft-core

env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" \
  swift test --package-path Packages/FiestaBoardAppState --disable-sandbox --scratch-path .build/draft-state
```

The Xcode project builds these same source files as native frameworks, with a framework resource accessor for DemoFixtures. This avoids a managed-environment SwiftPM manifest-cache write denial in Xcode; the packages remain independently host-testable. The store uses Apple Combine `ObservableObject`/`@Published` with a scene-owned `@StateObject`. This is a bounded deviation from the preferred `@Observable` design because this environment cannot launch Xcode’s compiler macro sandbox. `DraftState` is a typealias to the standard `SwiftUI.State<Value>` property wrapper: SDK 27.1 also defines a `State` macro, and the alias unambiguously selects the wrapper. No compiler sandbox or global filesystem permission is changed.

UI test source and the shared test scheme cover the demo compose confirmation and tab navigation on an iPhone-sized destination. In Xcode, choose an available iPhone simulator and Product → Test. The test can be compiled without launching a simulator:

```sh
xcodebuild -project FiestaBoard.xcodeproj -scheme FiestaBoard \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PWD/.build/draft-derived" CODE_SIGNING_ALLOWED=NO build-for-testing
```

The agent environment cannot access CoreSimulatorService. An unsigned generic Simulator build is possible, but simulator launch, UI test execution and visual QA were not performed. Do not interpret compiled UI tests as executed UI tests.

| Check | Automated coverage / manual work still needed |
| --- | --- |
| Transport and domain | Core fixture tests: URL security, cookies, version gate, receipts, demo outcomes |
| Store races and commands | Host tests: disconnect/server/board stale results, captured target/text, duplicate suppression, held/partial/rejected/unknown outcomes, readback lock, expired authentication, remote logout outcomes and late logout completion |
| Flap mapping | Exact punctuation/undefined codes, pigments, degree/heart code 62; Note models use heart |
| Generic iOS build | Unsigned SDK build, app/framework fixture packaging, UI test compilation |
| Geometry | Manual simulator/device check still needed: narrow portrait, short landscape, iPad split widths and large windows; no screen/device/orientation branching |
| Accessibility | VoiceOver board text, Dynamic Type, dark/light, Reduce Motion/Transparency require runtime review; static board has no animation/custom glass |
| Safe areas | Manual asymmetric safe-area/keyboard review still needed; native scrolling/navigation preserve system insets |
| Live server | No automated live writes; LAN/auth and physical output require an explicit user-run test with a compatible server |

Refresh is manual, with no foreground/background polling task. Navigation and the text draft live in the scene outside geometry-dependent layouts. Content surfaces remain opaque/readable; native tabs, sidebar and toolbars provide system Liquid Glass. Missing release work includes discovery, setup, OAuth, editors, conditional saves, scheduling controls, plugins, administration, pixel rendering and exhaustive hardware acceptance.
