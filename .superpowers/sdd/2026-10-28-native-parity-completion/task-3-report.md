# Task 3 / W1-A bootstrap, transport and onboarding

Implemented October 28, 2026. Initial actual HEAD: `713946b14575ad04f25fdb492d737de5275c5932`. Before scoped commit, shared integration HEAD: `54016e9db3cf3ba98841b02346b7cac280ced5f7`. Backend source read with `git show`/`git grep` at `b5eac069dce10945eac61e1fdadf6ee4a903ba08` only; no backend imports or backend tests ran on the host. Copied current sanitized `bootstrap-control.json` into Kit test resources. No live host, provider, hardware or browser interaction.

## Result and API

- `FiestaBoardService.bootstrap() async throws -> BootstrapSnapshot` has an unsupported default for existing mocks and a wholly local demo implementation. Live bootstrap reads exactly `/health`, `/discover`, `/auth/status`, all no-store; no board, version, page or optional library fetch. Stopped board service is valid. Every snapshot carries its immutable deployment identity. Cancellation stops the sequence; session changes reject delayed responses.
- `BootstrapSnapshot(deployment:health:identity:auth:)` exposes `phase`. Public `BootstrapPhase` cases: `chooseAuthentication`, `setupAdministrator`, `signIn`, `ready`. Undecided/first-run wins over administrator setup. Disabled auth is valid. Browser-cookie identities (`browser`, historical `session`, or legacy omitted auth kind) may be ready; TV and unknown kinds require sign-in.
- `ServerIdentity.init(product:version:installationID:name:) throws` and JSON decoding reject the wrong product with `.wrongProduct`. Empty installation ID/name are valid. Wire `id` becomes `installationID`. Public nonthrowing `ServerHealth.init(status:serviceRunning:version:)` and `BootstrapSnapshot.init(deployment:health:identity:auth:)` support UI/discovery tests.
- `AuthStatus` preserves optional `sessionManagementSupported`, `authKind`, `tvSignIn`; `TVSignInStatus` preserves supported/enabled/protocolVersion. Its public initializer defaults the additional fields to nil.
- `setAuthenticationPreference(enabled:setupToken:)`, `setupAdministrator(username:password:setupToken:)`, and `login(username:password:rememberMe:)` use exact source request shapes and require public auth-status readback. Old login overload explicitly sends `remember_me: false`. Failed readback after acknowledgment is unknown outcome, never automatic replay. Passwords/tokens are not persisted or logged. Persistent cookie consent/vault remains outside this task.
- `APIRequest` adds `context: APIRequestContext = .standard` and `cachePolicy: APIRequestCachePolicy = .default`. Context cases are `.standard`, `.onboardingToken(String)`, `.browserSession(origin: String, csrfToken: String)`. Cache adds `.noStore`. Onboarding proof is accepted only for POST auth/setup or POST auth/preference with enabled true. Arbitrary Authorization/Cookie/Host header overrides are unavailable. Control characters, malformed origins, proof on ordinary session/admin/read requests, and proof when disabling auth are rejected before network dispatch. Origin is emitted exactly as supplied; no inferred origin or stored CSRF. All redirects remain refused.
- New safe errors: `.unsupportedOperation`, `.invalidRequestContext`, `.wrongProduct`, `.setupRequired(firstRun:)`, `.onboardingConflict(.alreadySetUp/.modePinned)`, `.invalidCredentials`, `.setupProofRequired`, `.csrfRequired`, `.forbidden`, `.validation(fields:)`, `.startupUnavailable`, `.gatewayUnavailable`. `ValidationField` permits only username/password/enabled. Server detail strings are matched against source-known safe cases and discarded; arbitrary bodies/input/messages are never retained in errors. HTTP 401 auth loss, 409 domain conflicts, 412 page/collection conflicts, 429 Retry-After, 502 partial regions and unknown mutation barriers remain distinct. HTML cannot hide 401 or redirect status. HTML read failure differs from ambiguous mutation acknowledgment.

No candidate version/write gates changed. No AppState/UI/project files edited by this task. Root added Bootstrap.swift to the committed Xcode project in its separate scope.

## RED / GREEN evidence

1. Added public bootstrap/phase/current capability tests first; `.build/task3-red-bootstrap.log` records missing APIs before implementation. Initial attempted SwiftPM invocation also exposed restricted user cache/nested sandbox errors; explicit workspace cache paths and SwiftPM `--disable-sandbox` resolved that tooling issue.
2. Added bounded-header/safe-error tests before implementing context/error mapping; `.build/task3-red-transport.log` records absent context/error infrastructure during compilation. Initial public API REDs were compilation failures, not runtime assertion failures.
3. `.build/task3-red-identity.log`: runtime RED, public identity initializer failed to reject wrong product. Added initializer/decoder validation; GREEN in final suite.
4. `.build/task3-red-readback.log`: runtime RED, acknowledged setup with failed readback returned networkUnavailable rather than unknownMutationOutcome. Corrected readback handling; GREEN in final suite.
5. `.build/task3-red-html-status.log`: runtime RED, HTML 401 and HTML 302 mapped to gatewayUnavailable. Limited gateway mapping to successful/server-error responses; GREEN in final suite.
6. Full initial suite surfaced 3 failures: a new legacy test incorrectly used an already-extended auth fixture; two preserved login/logout tests used historical auth_kind=session. Corrected the omitted-field test input and preserved the historical cookie identity. Existing tests were retained.
7. Happy-path onboarding payload/readback, explicit remember-me, malformed acknowledgment, slow/cancelled bootstrap, demo and no-optional-library assertions also run in the final suite; some supplementary tests were green on their first execution.

## Commands and results

All commands ran from this worktree. Swift test flags below are literal for Kit; AppState/EditorState used the same shape with separate package/scratch/cache/config/security names.

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/task3-clang" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/task3-clang" swift test --disable-sandbox --package-path Packages/FiestaBoardKit --scratch-path .build/task3-kit --cache-path .build/task3-cache --config-path .build/task3-config --security-path .build/task3-security
env CLANG_MODULE_CACHE_PATH="$PWD/.build/task3-clang-appstate" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/task3-clang-appstate" swift test --disable-sandbox --package-path Packages/FiestaBoardAppState --scratch-path .build/task3-appstate --cache-path .build/task3-cache-appstate --config-path .build/task3-config-appstate --security-path .build/task3-security-appstate
env CLANG_MODULE_CACHE_PATH="$PWD/.build/task3-clang-editor" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/task3-clang-editor" swift test --disable-sandbox --package-path Packages/FiestaBoardEditorState --scratch-path .build/task3-editor --cache-path .build/task3-cache-editor --config-path .build/task3-config-editor --security-path .build/task3-security-editor
python3 -m unittest discover -s Tests/Contracts -v
python3 scripts/check-contracts.py
scripts/build-draft.sh device
git diff --check
```

- Kit: 80 tests, 0 failures (`.build/task3-kit-final.log`).
- AppState: 46 tests, 0 failures (`.build/task3-appstate-final.log`).
- EditorState: 50 tests, 0 failures (`.build/task3-editor-final.log`).
- Contract checker/runner tooling tests: 41 passed (`.build/task3-contract-tests.log`); these do not import the backend.
- Contract integrity passed (`.build/task3-contracts.log`); expressly not release ready.
- Initial unsigned device build failed because the app project omitted the newly added Bootstrap.swift. Root registered the file without changing signing. Fresh device build succeeded (`.build/task3-device-final.log`); benign AppIntents metadata extraction warning and restricted CoreSimulator service diagnostics remain in build output. No hardware test occurred.
- `git diff --check`: clean.

## Review, concerns and integration

Astra review requested through root for auth/error/credential boundary. Review outcome is owned by root; do not treat this report as reviewer acceptance. Native AppState/UI routing, credentials clearing, discovery adapters, Keychain/export/restore, fresh CSRF retrieval/consumption, and runtime phone acceptance remain later tasks. The caller must supply the externally configured exact Origin and a fresh proof for future browser-session mutations. No live connectivity or release claim is made.

Commit: scoped implementation/test commit recorded in the task handoff; this report is included in that commit. Other shared changes are excluded with explicit pathspecs and `git commit --only`.
