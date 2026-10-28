# Native draft testing

This is a runnable iOS/iPadOS 26+ SwiftUI draft built with Xcode 27.1 / SDK 27.1 and Swift 6. It covers demo mode, manual server connection, display selection, server-reported output, a page library with local on-device drafts, fixed-slot template editing, explicit validation/text preview and revision-checked page saves, native collection authoring with all three modes, text/page board actions, and pause, schedule-following, fallback-page and restore controls. It is not full web parity or a supported released server/app pairing.

## Open and run

From the repository root:

```sh
open FiestaBoard.xcodeproj
```

Select the shared **FiestaBoard** scheme, choose an installed iPhone or iPad simulator, and press Run. The scheme includes `--demo`, which creates a memory-only demo without a network session. Remove `--demo` under Product → Scheme → Edit Scheme → Run → Arguments to see Welcome and enter a server. The app never restores or automatically connects to a live deployment on launch.

The committed project is ready to build. The helper uses the existing project and preserves signing choices made in Xcode:

```sh
scripts/build-draft.sh simulator
# Compile against the device SDK without signing; this cannot install on a phone:
scripts/build-draft.sh device
```

Both commands set `CODE_SIGNING_ALLOWED=NO`. Build artifacts are `.build/draft-derived/Build/Products/Debug-iphonesimulator/FiestaBoard.app` and, if requested, `Debug-iphoneos/FiestaBoard.app`.

To install and run on your iPhone, use Xcode:

1. Select the **FiestaBoard** app target under **TARGETS**, rather than a framework target, and open **Signing & Capabilities**.
2. Keep your existing development **Team** selected and enable **Automatically manage signing**.
3. Select the shared **FiestaBoard** scheme and your connected, trusted iPhone as the run destination.
4. Press **Run**. Xcode builds, signs and installs the app using your selected team. Follow any device prompts, including Developer Mode if required.

Project regeneration is a separate step, only needed after changing `project.yml`:

```sh
xcodegen generate
```

Regeneration replaces project settings and can reset a Team chosen in Xcode; recheck signing afterward. Normal `build-draft.sh` builds never regenerate the project. No development team or signing credential is committed. There is intentionally no asset catalog or app icon in this draft.

## Demo walkthrough

1. Tap **Explore Demo**, or launch the shared scheme with `--demo`.
2. Home shows **Demo Kitchen**, its server-reported output, selected/resolved/scheduled page distinctions, and a simulated connection banner.
3. Compose text, enter `HELLO`, then **Review action**. Confirm the captured server, board ID and exact text; **Confirm simulated action** changes only memory. The result says whether a send was acknowledged and never claims physical observation.
4. Open Library, search `Sunny`, open **Sunny day**, and simulate showing it on the selected board. The detail screen shows template source. Tap **Edit local draft** to fetch its full raw document. Change the name or supported fixed template lines, use Undo/Redo, and **Save local draft**. Close and reopen to review draft recovery. Local save stays on this device. Closing with unsaved changes requires save, discard or keep editing.
5. In the page editor, explicitly choose **Demo Kitchen** under **Board for evaluation**. **Validate** and **Preview** evaluate the current document only when requested. Demo evaluation is labeled simulated: it shows literal template text and does not evaluate dynamic expressions/plugins or draw canvas content. Choose **Simulate saving page**, inspect the confirmation, and cancel or **Simulate save**. The editor saves a local snapshot before attempting the save; acknowledgement updates its server baseline and clears obsolete undo history. Local recovery checkpoints and server storage have separate dirty indicators. Saving stored page content does not directly send a board command, though running displays may later use that content.
6. To inspect conflict recovery, close the editor, choose **Rejected** in Settings, reopen a page and change its name. Confirm **Simulate saving page**. The conflict preserves the edited local draft and prevents another save. **Fetch server page for comparison** shows a separate comparison without replacing the editor. **Reload compared page…** → **Preserve local draft and reload** explicitly adopts the fetched revision and clears undo history while preserving prior local work. **Unknown** or **Partial** simulates an uncertain page save that may already have been stored; fetch before deciding to reload. No mutation is automatically retried.
7. From Home, open **Board controls**. Pause/resume, follow/disable the schedule, change or clear the fallback page, and restore content each require confirmation of the captured board and deployment. Cancel leaves the board unchanged. Restore retains the pinned page and respects pause/silence; it does not promise a send. These controls simulate changes in demo mode and use the existing write gate on a live server. The same screen shows pending requests and outcomes. If an outcome requires readback, its actions remain disabled while **Refresh board state** stays available; refreshing never repeats the mutation. In Settings, choose **Unknown**, return to Board controls and pause: the unknown-result message and readback prompt remain visible until refresh reveals the changed pause state. A restore while paused reports the refusal on this screen.
8. Open Displays and use **Demo Pixel Panel**. Its unsupported character set is explained rather than displayed as a flap approximation. Switch back to Demo Kitchen.
9. In Settings, choose a simulated outcome: accepted, held, partial, rejected or unknown. Held selection remains distinct from reported output. Partial and unknown results require **Refresh output** before another action. Refresh reads state and never replays a mutation.
10. Disconnect. A new demo starts server simulation from the bundled fixtures; saved on-device drafts remain available for recovery.

Demo Kitchen uses a 6 × 22 split-flap welcome frame with color cells. Simulated text wrapping is simpler than backend layout. Demo board actions, page saves and evaluations are labeled simulated. Demo page changes persist only in memory until disconnect; local recovery files remain on device. The split-flap table is reused from the TV project under its [MIT license](../ThirdPartyNotices/FiestaBoardTV-MIT.txt); this app does not claim TV renderer parity.

## Collection walkthrough

1. Open **Library → Collections**. Demo includes simulated collection data; the list supports name/ID search and refresh.
2. Choose **Create collection**, name it, add member pages and reorder them. Pick Time, Variable or Random. Variable rules run in order and have a member-page fallback and polling interval. Expressions are server-owned; demo does not claim to evaluate plugins.
3. Use **Simulate saving collection…** and review the confirmation. Acknowledgement means collection storage, with board selection still separate. Reopen the collection to edit it; deletion also needs confirmation and respects in-use refusals.
4. Close a changed editor to keep its local checkpoint or explicitly discard it. Recovered work retains its original baseline/revision. Comparing the server does not merge or retoken the draft; adopting a comparison explicitly preserves the previous local copy.
5. In Settings, the simulated Unknown/Partial outcome can exercise uncertain collection storage. Do not repeatedly save: inspect the collection list. An uncertain create may already exist; close with its draft preserved, review the refreshed list and start a deliberate new draft if necessary. The old draft cannot replay.

On a live deployment, enable **Enable changes on this server** in Settings. New collection creation currently requires the audited non-development 10.1.7 candidate. Existing edits/deletes require collection-revision-v1, supported fields and the original revision. Board controls keep their independent version gate. No live server or board was changed by the automated verification for this milestone.

## Connect to your server

Remove `--demo` from the scheme and use **Manual server connection**. Enter the deployment root with scheme, port and any reverse-proxy prefix, for example `https://board.example.com/fiesta`. Do not append `/api`; the app adds `/api` after the deployment prefix. URL credentials, query strings, fragments, path traversal and percent-escaped prefixes are refused.

HTTPS uses normal system trust and is required for public hosts. For a local HTTP server, explicitly enable **Allow HTTP on my local network** and enter a permitted local address such as `http://fiestaboard.local:5000`. The app declares a local-network purpose and allows local networking only; it has no arbitrary-load ATS exemption. On a phone, `localhost` refers to that phone, not your Mac. Use the server’s LAN address and grant the system local-network prompt when appropriate. No Bonjour discovery, server setup or OAuth flow is implemented.

Enter username/password if the server requires login. Passwords are removed from the form immediately after starting an attempt and are never persisted. Cookies use an isolated, ephemeral, memory-only session scoped to the complete deployment identity, including port and proxy prefix. Each app window owns a separate store/session. **Disconnect** drops the local session; **Log out & disconnect** also attempts to revoke the old server session. Welcome shows whether that sign-out is pending, confirmed or could not be confirmed; failed sign-out may leave the server session active. A late result from the old server does not replace a newer connection. If any read or action discovers expired authentication, the app disables controls and returns to the connection form to sign in again. An acknowledged send remains acknowledged if its later readback loses authentication, and is never replayed. No session restoration or Keychain storage is implemented.

Every new manual connection starts with server changes disabled. Settings → **Server changes** exposes an explicit **Enable changes on this server** opt-in and **Apply change setting**. Applying reconnects, creates a new connection generation and enables only the capabilities that pass their independent checks:

- Page saves require the fetched page to advertise the exact `edit_protocol: "page-revision-v1"`, a nonempty original revision and the session opt-in. The native editor sends only changed supported `name`/`template` fields with that expected revision. Unknown or absent protocols remain unable to receive page saves. Server storage acknowledgement is distinct from board delivery; displays may later use the stored content.
- Board controls require the separate exact non-development `running_version` of `10.0.0`. Other versions, including the observed 9.14.9 read-shape server, keep board controls read-only even with opt-in. A known page protocol can permit page saves on such a server without enabling board controls. The version string is a draft schema gate, not proof of backend commit identity or release support.

Each server save and board action needs its own confirmation. Review the captured deployment, page or board, and content before confirming. A page conflict or uncertain outcome preserves local work and requires explicit server comparison; fetching never silently adopts a new baseline or resubmits edits. Disconnecting, reconnecting to the same URL, authentication loss or switching deployments invalidates old editor contexts. Validation and preview use the existing evaluation endpoints with an explicit board target; they do not use live rendering or send board content.

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

Documents, local-draft and editor-coordination host tests can also run independently:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" \
  swift test --package-path Packages/FiestaBoardDocuments --disable-sandbox --scratch-path .build/draft-documents

env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" \
  swift test --package-path Packages/FiestaBoardEditorState --disable-sandbox --scratch-path .build/draft-editor
```

The Xcode project builds these same source files as native frameworks, with a framework resource accessor for DemoFixtures. This avoids a managed-environment SwiftPM manifest-cache write denial in Xcode; the packages remain independently host-testable. The store uses Apple Combine `ObservableObject`/`@Published` with a scene-owned `@StateObject`. This is a bounded deviation from the preferred `@Observable` design because this environment cannot launch Xcode’s compiler macro sandbox. `DraftState` is a typealias to the standard `SwiftUI.State<Value>` property wrapper: SDK 27.1 also defines a `State` macro, and the alias unambiguously selects the wrapper. No compiler sandbox or global filesystem permission is changed.

UI test source and the shared test scheme cover demo compose confirmation, tab navigation, local-draft entry and unsaved-close handling, explicit board selection and simulated template preview, cancelled/confirmed page save, conflict comparison and explicit reload, and board-control cancellation/confirmed pause, unknown-configuration readback recovery and paused-restore refusal visibility on an iPhone-sized destination. In Xcode, choose an available iPhone simulator and Product → Test. The test can be compiled without launching a simulator:

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
| Documents/local drafts/editor | Host tests cover lossless documents, bounded edits, local persistence, save/conflict/unknown-result handling, explicit reload, revision and stale-evaluation races; runtime recovery, TextKit/IME, keyboard and rotation checks still needed |
| Generic iOS build | Unsigned SDK build, app/framework fixture packaging, UI test compilation |
| Geometry | Manual simulator/device check still needed: narrow portrait, short landscape, iPad split widths and large windows; no screen/device/orientation branching |
| Accessibility | VoiceOver board text, Dynamic Type, dark/light, Reduce Motion/Transparency require runtime review; static board has no animation/custom glass |
| Safe areas | Manual asymmetric safe-area/keyboard review still needed; native scrolling/navigation preserve system insets |
| Live server | No automated live writes; LAN/auth and physical output require an explicit user-run test with a compatible server |

Refresh is manual, with no foreground/background polling task. Navigation and the text draft live in the scene outside geometry-dependent layouts. Content surfaces remain opaque/readable; native tabs, sidebar and toolbars provide system Liquid Glass. Local editors fetch the full raw page response, capture its deployment/page identity, and keep edits outside geometry-dependent layouts. Disconnect, authentication loss or changing connections closes the editor; stale fetches cannot open a document for a new connection. Local drafts use atomic on-device files, not server persistence. Unsupported content remains read-only; template expressions stay raw. Supported server saves use the loaded original revision and exact protocol. Rich visual content remains read-only; the text preview reports visual layers and warnings rather than drawing an approximate canvas. There is no schedule editor.

Missing release work includes discovery, setup, OAuth, full page/layout editors, schedule editing, plugins, administration, pixel rendering and exhaustive hardware acceptance.
