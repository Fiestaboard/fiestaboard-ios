# Native UI fixture resources

`retained-ui.json` contains the previous test replay's synthetic board artwork,
page documents, catalogs and render table. It was extracted from the four
`Tests/UITests/fixture_*.py` modules at `f94ad39`, preserving their values. It is
**not** a live-hub recording or a renderer implementation. Unsupported formulas
still render `???`; the one explicit accessory formula retains its documented
synthetic output.

`FixtureRouter`, `FixtureBoardRoutes` and `FixtureRenderRoutes` preserve the
stateful behavior (prefix namespaces, board actions, revision writes, flexible
unknown blocks/numbers, render fallback and catalogs). Migration controls under
`Tests/Tooling` compare the native responses to exported historical outputs.

The separate `Tests/Fixtures` resource folder holds the byte-exact I5 mobile
recordings and SOURCE provenance. `/recorded-<filename-without-json>/api/<path>`
serves the matching recorded method/path, status, headers and response bytes
without rewriting the token. Those credentials were synthetic and revoked by
the recorder. The retained editor scenarios issue separate test-only,
namespace-bound `fb_mob_fixture_*` bearer tokens; they do not claim recorded
credential identity. Their cookie auth path has been retired.

`FixtureHTTPServer` is adapted from the tvOS Network listener and runs in the
XCTest runner, on an OS-assigned loopback port. UI helpers use that live port;
there is no shell-launched Python replay or fixed fixture port. Per-prefix UUIDs
isolate test state; `setDropped` lets a test simulate a disconnected hub. Parser
controls exercise split request bodies and connection-drop using real host
sockets. Native iOS app/test-runner composition still requires simulator CI.

I8 Compose namespaces (`/board-i8-compose-<UUID>` and
`/board-i8-compose-unknown-<UUID>`) reuse the existing namespace-bound mobile
fixture login. The I8 router loads the immutable `Tests/Fixtures/Compose`
operation, long-LED and catalog recordings. Matching preview and catalog requests
return the recorded raw response bytes; device drawing facts are retained.
The display names, arbitrary split-flap typing previews, dynamic receipt UUID and
clock, and Save-as-Page copy/readback are explicitly synthetic navigation glue.
Unsupported LED input has no invented preview. Mobile raw array hydration keeps
its recorded 403; no sample/current-value/index fallback is supplied. Duplicate
UUID POSTs are refused and outcome GETs do not dispatch a send. These fixtures
are not live hub, physical display, scrolling, or performance evidence.
