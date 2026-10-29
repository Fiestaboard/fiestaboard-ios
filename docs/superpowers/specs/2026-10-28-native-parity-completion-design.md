# Native parity completion design

Status: approved by the user on October 28, 2026 for continuous end-to-end implementation. This extends the user-approved October 25 native design; it does not authorize publishing or claim release readiness. The user explicitly reaffirmed rich editing for both split-flap and LED.

## Outcome

Deliver `fiestaboard-ios` as a universal native SwiftUI app that can find an existing FiestaBoard server, sign in, operate its boards, and perform every user-visible web workflow. Full web parity is required before the first App Store release. Intermediate builds must deliver usable end-to-end journeys, beginning with finding/signing into/controlling the user's board.

“Clone” means both equivalent product capabilities and a reproducible fresh repository checkout. It does not mean copying the web's widgets or running the server on the phone. Native equivalents for browser installation, routing, location, files, sharing and fullscreen are explicitly included.

## Existing decisions and approaches

The user already chose native Swift, Apple design/glass, universal iPhone/iPad layouts, all useful available device/window poses, complete web parity, Sol 6.1 implementation and Astra review. Continue the approved native-client/server-runtime architecture. A WebView wrapper does not meet that choice; duplicating templates/plugins/scheduling on-device would create divergent behavior. Neither alternative is being reopened as a product decision.

The execution approach is end-to-end slices: complete connection/control before deepening content and administrative workflows. Building all screens before integrating them would leave the user's immediate connection problem unresolved. Refine each wave into reviewable changes with fixtures and failure handling, then integrate a runnable draft.

## Baselines and truthful status

| Reference | Meaning |
| --- | --- |
| Native `116b075` | Current integrated draft: manual login, memory-only sessions, bounded board controls, narrow template edits, Collections, recovery. |
| FiestaBoard 10.0.0, `2ced809c8fe20d4ac6e5dc6603d691c8cb4e475a` | Committed original contract inventory: 81 workflows, 198 method/path pairs. Historical evidence; not an accepted release pairing. |
| FiestaBoard 10.1.7, `79edd37d2329eaa34f42081a4d48e87bc04bb455` | Scoped collection/create/preview fixture candidate after backend PR #2373 merged. |
| FiestaBoard 10.1.17, `b5eac069dce10945eac61e1fdadf6ee4a903ba08` | Proposed complete-parity target, observed on upstream main October 28 through `gh`. Not yet an accepted native contract or the user's confirmed deployed version. |

The last completed milestone recorded 186 Swift host tests, 29 native contract-tool tests, 55 isolated backend fixture cases, unsigned Simulator/device builds, and seven UI tests compiled with zero executed. These are historical results, not newly executed tests for this document. Astra accepted the bounded core/editor changes. Runtime layout, VoiceOver, real discovery, remembered sign-in, full server compatibility and physical end-to-end control remain open.

Current board commands accept exact non-development 10.0.0, while collection creation accepts the scoped 10.1.7 candidate. Fix this through a tested current-version adapter/contract wave, not by removing guards. The committed parity JSON still labels all 81 rows planned: it is a release acceptance ledger, not a measure of how much code exists. Do not report a percent complete from it.

Refresh the complete schema/operation/source inventory to the proposed 10.1.17 target before claiming current-web coverage. The source delta from 10.1.7 includes filled-color token 71/editor handling, display/override controls, plugin-cache/breaker behavior, and offline/integration presentation. Preserve old fixture evidence separately. Future upstream changes enter a dated delta queue; do not silently move the release target or silently omit features from the chosen reference. The installed server version is a separate fact to obtain during the first device walkthrough.

## Architecture and ownership

- Swift 6, universal iOS/iPadOS 26 minimum; current repository toolchain Xcode/SDK 27.1. Validate availability guards and deployment target in CI. Use the repository's existing state approach unless a reviewed change is needed.
- SwiftUI native navigation/forms/glass; selective UIKit/TextKit for lossless rich editing. Server owns template evaluation, canvas rasterization, scheduling, integrations/provider tokens, AI tools and device communication.
- `FiestaBoardKit` owns deployment identity, typed DTOs, transport, adapters and fixture-backed behavior. AppState owns scene contexts, resource coordination and stale-result rejection. Documents owns lossless JSON and durable recovery. EditorState owns authoring/undo/conflict state. Feature views own presentation.
- New connection/session and schema/renderer units get focused files/packages only when their responsibilities warrant them. Keep credentials and live transport out of views and editor documents.
- Scene-local navigation/drafts; explicit deployment/resource cache keys; central session/resource mutation coordination across windows. A second scene cannot accidentally inherit a different server's cookies, write opt-in or resource revision.
- Public v1 where semantics fit, exact version-bounded adapters for required internal endpoints. Capability/protocol claims are necessary where applicable and are not universal authorization. Unknown versions receive only independently verified capabilities.

## First usable journey

Fresh launch → Find FiestaBoard or enter/paste server URL → inspect identity/transport → sign in or complete first-run setup → choose board → view server-reported output → explicitly enable supported changes → send test text → inspect acknowledgement/readback → quit/reopen → reconnect without typing the address/password again when Remember sign-in was chosen → log out and verify local/session cleanup.

Discover the FiestaBoard server, not physical output devices. Server mDNS currently publishes `_http._tcp.local.` with TXT `product=FiestaBoard`, `path=/`, default port 4420 (`src/system/mdns.py`). Verify candidates with the actual unauthenticated `/discover` contract. Do not assume a fabricated `_fiestaboard._tcp` service or that every Docker/proxy install advertises. Preserve a manual URL path and optional server sharing/QR path; no subnet port sweep is necessary. Display hardware discovery belongs to server-side output actions later.

User initiation starts browsing and local-network permission. Model searching/results/none/not-enabled/error/cancel; the platform may not reveal the exact permission cause, so avoid claiming denial from an ambiguous browse failure. Saved server metadata is separate from secrets. Keep session material in a deployment-scoped Keychain store only for explicit Remember sign-in; never save the password. Test cookie expiry, refresh/revocation, path/domain/Secure semantics and browser/proxy authentication separately.

Direct LAN discovery cannot discover remote public endpoints or bypass Home Assistant ingress. User-provided HTTPS/VPN is the remote access model. W0-C owns early authenticated-HA route/bridge feasibility and any required native implementation; actual upstream proof may need its operator and remains required. A prefixed URL or rewriting mock is not that proof. This does not block independent direct-LAN work.

The first supplied test endpoint is `http://fiestapi.local:4420`. Initial unauthenticated health/discover/auth-status probes returned No route to host from this environment; installed version is not established and no credentials were sent. Resolve reachability with the user/device while isolated development continues; keep supplied credentials outside the repository.

## Complete scope and acceptance

[The master checklist](../../native-parity-checklist.md) covers every one of the original 81 workflow IDs, platform/release work, critical journeys, and new-source reconciliation. [The execution plan](../plans/2026-10-28-native-parity-completion.md) defines dependencies, file ownership and delivery order. `TASKS.md` is the short current queue; these documents do not replace source/schema release evidence with prose checkmarks.

Each workflow needs equivalent reachable native UI, typed request/result behavior, recoverable error/empty/loading/offline states, multi-server/target correctness, replay and concurrency handling, and a recorded UI/device acceptance result. “Implemented”, “built”, “unit/fixture tested”, “runtime UI tested”, “physical verified” and “release accepted” are separate evidence levels. A compiled UI test is not a passed UI test.

Unknown write outcomes never authorize automatic replay. Loaded original revisions remain attached to drafts across comparison; reconnect or a fresh GET cannot retoken an old edit. Unsupported content is preserved or edit-blocked. A storage acknowledgement, a selected page and a physically observed frame are separate facts. Provider browser success is separate from native status refresh. Local cleanup failure must not turn an acknowledged write into a replayable write.

Complete all fourteen web locales (en/es/fr/de/it/pt/nl/pl/ru/sv/tr/ja/ko/zh), accessible alternatives to drag/draw/calendar actions, and correct split-flap/Note-array/panel/LED/white-board output including filled token 71. Prove TextKit/token/IME/undo/canonical round trips before building the full editor around it.

### Required rich-editor proof for both output families

Rich authoring is required for split-flap and LED, including the upstream-supported text/token/expression/color/formatting controls for each family. LED must not fall back permanently to a raw-template-only editor. Split-flap's glyph/color/cell constraints must not be flattened into LED semantics, and LED formatting must not be silently lost when switching target or rich/plain presentation. Derive exact supported controls from current web/server fixtures, including configured charsets, spans/icons/visual layers where supported. Preserve unsupported document content or block unsafe changes with a reason.

Run the full rich/plain/IME/paste/selection/undo/preview/conditional-save/conflict/recovery/resize matrix separately for split-flap and LED documents. Both have to round-trip faithfully and produce server-validated previews before this editor milestone can be accepted. Record separate visual/device evidence and source-backed differences; a successful split-flap editor does not accept LED by inference.

## Layout and Apple alignment

Use available container size, safe areas and actual SDK capabilities. Cover compact portrait, compact landscape/short-wide, wide/open, continuous resizing, iPad multitasking/multiwindow and external keyboard/pointer/Pencil. Preserve draft, undo, selected resource, scroll/focus and captured destination through geometry changes. Include seated/part-folded/tent poses only on hardware/SDKs that expose usable geometry; no promised hinge API, invented device SKU or fabricated hardware-test result.

Glass belongs primarily to system navigation/toolbars and selected controls. Keep previews, editing surfaces and forms readable, with light/dark, Dynamic Type, Reduce Motion/Transparency, increased contrast and VoiceOver. Follow [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Liquid Glass guidance](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass). Local-network service declarations/device validation follow [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Working method and interactions

At most two bounded Sol 6.1 implementers, with one integrator and one Astra reviewer slot. Establish shared interfaces before parallel changes. Sol fixes findings; Astra rechecks substantive auth/editor/concurrency changes and each milestone. User-requested Claude Opus CLI work is optional when authenticated; prior attempts failed with expired authentication and no contribution is claimed. Its absence does not block Sol progress.

Keep an evidence/status ledger in the repository. Every accepted work package records source/app commit, automated commands/results, reviewer verdict, unexecuted manual cases and remaining blockers. Group related CI failures and use Jev selectively under the configured rules; advice never replaces tests or a review.

Continue all independent authorized work when one item needs user interaction. Record the exact blocker, requested input and unblocked work; ask at the point it is useful, not as a global stop. Device networking/permission prompts, provider authorization, actual HA ingress, Apple identity/distribution and hardware-destructive acceptance may need the user. Never put credentials in a document or chat request. Publishing, a production deployment and device-affecting test runs remain distinct explicit actions.

## Completion and release

The app is end-to-end usable when the first journey is observed on a real iPhone against a known installed server, not merely when package tests pass. It has feature parity only when every workflow in the frozen reference and platform equivalents passes its acceptance evidence, with zero unaccepted omissions. It is release-ready only after supported API/topology/OAuth/physical evidence, CI/archive, performance, accessibility, localization, privacy/assets and distribution checks also pass.

Fresh clone must build/test from committed configuration and documented pinned inputs without this Mac's ignored `.reference`, `.build`, local cookies or developer Team edits. The shared normal scheme opens connection onboarding; demo has an explicit separate entry. Preserve the user's current Xcode signing selections during all integration. Repository organization/visibility and production bundle identity remain release-management inputs, not reasons to postpone implementation.

App Review preparation includes a maintained review server/demo account or complete demo and the hardware demonstration/access required by [Apple's review access guidance](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/). Account, purchase and privacy obligations are checked against the actual shipped behavior; no new cloud service or payment model is assumed. Submission is a separate user action.
