# FiestaBoardKit draft

Swift 6 pure transport/domain/services for iOS 26+, testable on macOS 15+. No external dependencies. This is a bounded native draft, not full web parity or a supported released app/server pairing.

The app consumes `any FiestaBoardService`. `LiveFiestaBoardService` is an actor tied to one immutable `DeploymentURL`; create a new service when changing deployments. Call `authStatus()`, sign in if required, then `connect(allowCandidateWrites:)`. A `BoardTarget(deployment:boardID:)` binds a concrete board ID to the full deployment identity. The alias `primary` is deliberately rejected for mutations.

`connect` validates the board-list projection. Every unknown/9.x version stays read-only. Only an exact non-development `running_version == "10.0.0"` may enter `candidateWrites`, with explicit opt-in. This is a draft candidate gate, not release support. Login/logout and deployment changes reset write authorization; reconnect explicitly after login. A service must not be reused across deployment identities. UI consumers should also discard in-flight view updates when replacing their service.

`BoardDetail` keeps `activePageID`, `scheduledPageID`, `resolvedPageID`, `characters`, `expectedCharacters` and `readAt` separate. Server-reported content can be cached and is not independent confirmation of hardware output. Geometry comes from the server. `renderingSupport` permits the draft flap renderer only for a matching grid, `vestaboard_v1` codes 0...71, and no pixel layers. Other character sets/pixel devices remain explicitly unsupported by that renderer; their original data and layers are preserved. Page models are read-only projections and must not be used for editor round trips.

Mutation results distinguish accepted, held, not sent, and selection stored without delivery. `sent` means the server reported accepting a write, not physically observed output. Partial writes, known rejections, unauthenticated responses, conflicts, throttling, and unknown outcomes are typed errors. A lost connection, malformed mutation receipt, uncertain 5xx or mutation redirect must be refreshed before deciding to send again. No application retries or mutation replay are implemented.

`DemoFiestaBoardService()` throws if its bundled fixtures are invalid. It never creates a network session. Its status uses `isDemo == true` and `access == .simulated`; all controls must be labelled simulated. `setSimulation(_:)` selects accepted, held, partial, rejected or unknown results. It contains two representative boards and pages, including a pixel board whose renderer is unsupported. Text layout is a simple deterministic demonstration, not server word-wrap parity. Demo changes disappear when the service is recreated.

Sessions use isolated ephemeral URLSession contexts and an explicit in-memory cookie jar scoped to the entire deployment identity, including port and prefix. Only `fiestaboard_session` is retained; passwords are never persisted. Cookies honor host-only/domain, path boundaries, Secure and expiry/deletion. Explicit Domain cookies must equal the issuing host; parent-domain cookies are deliberately refused. Redirects and HTTP authentication challenges are refused. System TLS trust validation remains in place. URLs with credentials, queries, fragments, traversal, percent escapes or unsafe API path segments are rejected. Local HTTP needs explicit opt-in and a loopback/private/link-local/.local address.

Keychain session persistence, Bonjour discovery, first-run account setup, Home Assistant ingress authentication, OAuth, editor saves/revision preconditions, administration, exhaustive device rendering and physical-device verification are not implemented. No supported-version/release claim follows from these fixture tests.

Run from the repository root:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
    SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module" \
    swift test --package-path Packages/FiestaBoardKit --disable-sandbox --scratch-path .build/draft-core
```

Fixtures are synthetic, hand-authored from the pinned v10 contracts and source, not recordings from physical hardware. The adapter is grounded in archived FiestaBoard commit `2ced809c8fe20d4ac6e5dc6603d691c8cb4e475a`, the [pinned public schema](../../Contracts/public-openapi.json), and the [pinned internal schema](../../Contracts/mobile-internal-openapi.json). `/api` is the proxy prefix added after the deployment prefix; the paths below are schema paths.

| Method and schema path | Exact pinned source | Bounded use |
| --- | --- | --- |
| `GET /auth/status` | `src/auth/routes.py:259`, `src/auth/routes.py:39` | Auth/setup state projection; no setup writes |
| `POST /auth/login` | `src/auth/routes.py:346`, `src/auth/routes.py:54` | Username/password; `remember_me:false` |
| `POST /auth/logout` | `src/auth/routes.py:370` | Revoke current cookie session |
| `GET /version` | `src/system/routes.py:85`, `src/system/models.py:14` | Running version and exact candidate gate |
| `GET /v1/boards` | `src/v1/routes_boards.py:102`, `src/v1/models.py:33` | Board IDs, geometry, output profile |
| `GET /v1/boards/{board}` | `src/v1/routes_boards.py:126`, `src/v1/models.py:84` | Server-reported output/selection projection |
| `GET /v1/pages` | `src/v1/routes_content.py:52`, `src/pages/models.py:355` | Read-only library projection |
| `GET /v1/pages/{page_id}` | `src/v1/routes_content.py:83`, `src/pages/models.py:114` | Read-only page projection |
| `POST /v1/boards/{board}/message` | `src/v1/routes_boards.py:398`, `src/v1/models.py:190,298` | Only `{ "text": ... }`; no override flags |
| `PUT /v1/boards/{board}/active-page` | `src/v1/routes_boards.py:743`, `src/v1/models.py:362,377` | Only `{ "page_id": ... }`; stored selection vs immediate send |

The [web operation inventory](../../Contracts/operations.json) records exact web-client calls. Its auth/version/page/message entries were inspected. The board-list/detail and active-page routes are canonical public native alternatives grounded in the pinned schema/source; their absence from that web-call inventory is not a claim of runtime verification. All Swift fixtures are synthetic, and the native adapter remains a draft candidate.
