# Native collection contract evidence

The scoped candidate is FiestaBoard **10.1.7**, immutable source
`79edd37d2329eaa34f42081a4d48e87bc04bb455`. Git ancestry confirms that merged
PR #2373's `e6d51d3ce0d0c2be2a434fc67109416505b1b557` is an ancestor.
The archive's `src/__init__.py` and `package.json` both report 10.1.7.
The 11 source hashes recorded in the corpus match the corresponding immutable
Git objects, checked without importing backend code on the host.

This is workflow evidence for native collection editing and the existing
validation/preview input subset. It does not promote the release-wide server
matrix, change the original 10.0.0 baseline, authorize board writes, or establish
real native authentication, Home Assistant, OAuth, deployment or hardware proof.

## Corpus and reproduction

[`Fixtures/contracts/collections-v1.json`](../../Fixtures/contracts/collections-v1.json)
contains 55 request/response value cases. Each case has a stable `id`, a
`request` (`method`, `path`, optional `body`/`query`), and a `response`
(`status`, `body`). Collection IDs, revisions, board IDs and timestamps are
sanitized. Truncated Pydantic runtime-model representations containing clock
values are redacted inside two diagnostic strings; diagnostic text, Unicode
input, ordered arrays and nulls are preserved. Opaque fixture revisions are
examples, never tokens that a client may manufacture.

The generator and replay entry points live in
[`Tests/Contracts/test_collections_fixture.py`](../../Tests/Contracts/test_collections_fixture.py).
Regular host discovery imports only the standard library and checks native
fixture integrity. Backend imports require both Docker and the explicit marker.

From this worktree, run the replay with the immutable image ID currently tagged
`fiestaboard-ios-contract:clean`:

```sh
docker run --rm --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,size=1g \
  --workdir /app --env PYTHONDONTWRITEBYTECODE=1 --env PYTHONPATH=/app \
  --env HOME=/tmp --env COLLECTION_CONTRACT_DOCKER=1 \
  --env FIESTABOARD_OUTPUT_SEED_DIR=/opt/fiestaboard/seed/outputs \
  --mount "type=bind,src=$PWD/.reference/FiestaBoard-v10.1.7,dst=/app,readonly" \
  --mount "type=bind,src=$PWD/Tests/Contracts,dst=/native-tests,readonly" \
  --mount "type=bind,src=$PWD/Fixtures/contracts,dst=/contract-fixtures,readonly" \
  --entrypoint python \
  sha256:1f007c0360343d3d5b5263f04a370564dc36754fd61420b48a6ef7545981ff9d \
  /native-tests/test_collections_fixture.py --replay
python3 -m unittest discover -s Tests/Contracts
```

Replacing `--replay` with `--generate` emits a newly sanitized corpus on stdout.
Review that output before replacing the committed fixture. The image uses
Python 3.14.9, FastAPI 0.162.0 and Pydantic 2.14.1. All stores are created in a
container `TemporaryDirectory`. The backend archive and native files are
mounted read-only; the container has no network and no app lifespan is started.

The test app mounts the actual public v1 router and private template router.
It exercises their real validation, services, file stores, content-reference
checks and template expression engine. Plugin data construction is fenced to
an empty context and rejects attempts to request a provider. No board send or
live render endpoint is called. Authentication middleware is outside this
focused harness; existing authentication evidence remains separate.

## Wire and validation findings

| Operation | Exact scoped contract |
| --- | --- |
| GET `/v1/collections` | 200, `{collections: [...], total: n}`, case-insensitive name sort |
| GET `/v1/collections/{id}` | 200, bare collection; missing is 404 |
| POST `/v1/collections` | 201, bare collection with server ID, revision and `collection-revision-v1` |
| PUT `/v1/collections/{id}` | 200, bare collection; original `expected_revision` belongs in the JSON body |
| DELETE `/v1/collections/{id}` | 200, `{id: ...}`; original `expected_revision` belongs in the query |
| Conflict / in use / missing | 412 / 409 / 404 respectively; each uses `detail` |

The canonical full known-field write has `name`, ordered `page_ids`,
`selection_mode`, a non-null `time: {interval_seconds}`, and nullable `variable`
and `random`. Variable config has ordered `rules: [{expression, page_id}]`,
`default_page_id` and `poll_seconds`. Random config has `interval_seconds`.
Explicit JSON null clears `variable` and `random`; omitted fields preserve
existing values on partial updates. A mode switch must supply its required
config and deliberately clear inactive configs. Both null-clearing paths have
recorded successful responses. `time: null` is not the canonical native write;
the backend's update merge treats it as preserving the existing time config.

Names are 1–100 Unicode code points (Swift Unicode scalars for valid JSON
strings), with no trimming. A single space is accepted. 100 astral emoji pass,
101 fail; 50 decomposed `e` plus combining acute pairs pass (100 scalars), and
51 fail. Member lists must be nonempty, unique, refer to existing pages and
exclude collections. Time/random durations include 5 through 86400 seconds;
variable polling includes 2 through 600 seconds. Outside values return 422.
Missing active-mode config returns 400 after domain validation. Unknown mode
strings are rejected with 422 by this backend's request Literal.

Rule/default membership and real expression syntax are validated before
storage. Bad references/expressions return 400. The expression engine uses
ordered first-match semantics; a test with two true rules selects the first
member. Empty rules select the fallback. Time member order and two-member
random alternation are checked with explicit timestamps and no provider data.
The harness does not attempt native reimplementation of server evaluation.

Successful updates change the opaque generation; failed writes retain it.
Reloading the persisted store through the backend hydration path changes it.
Deleting and recreating the same ID changes it and rejects the old token.
Runtime `revision`/`edit_protocol` are absent from the persisted document.
The reload evidence is an in-process reconstruction of the storage hydration
behavior, not a deployed-server restart experiment.

Deletion checks generation before checking references. The corpus records
both stale deletion (412) and an actual saved active-selection refusal (409)
followed by successful deletion after explicitly removing the test reference.
Source `content_references.py` also checks schedules (including disabled
entries), schedule defaults, collection references, silence settings and
temporary overrides. Those additional reference kinds are source-audited,
not individually exercised by this corpus.

## Runtime capability and native gates

Reads and runtime protocol advertisement are distinct from the create gate.
This backend permits legacy unconditional writes when `expected_revision` is
omitted; the native client must always retain the original nonempty revision
for existing-resource writes. A list refresh cannot authorize an older draft.
Creates lack an existing resource to advertise a protocol, so native creation
requires explicit session write opt-in and exact audited **non-development
10.1.7**. Unknown/newer/development releases must not inherit that permission.
The existing board-control exact-version policy remains independent.

Unknown native mode strings should remain readable with editing disabled.
This fixture only claims known collection-field parity. Backend typed models
do not promise arbitrary unknown JSON field round-tripping; malformed/future
stored collection records are preserved on disk but may be omitted from typed
API reads. Neither behavior justifies silently converting future content to a
known writable mode.

## Existing validate/render adapter audit

The actual 10.1.7 template models accept the existing native adapter's allowed
input subset: validate accepts `template` string/list plus `board_id`; render
also accepts device/note/panel geometry, `line_metadata` and `canvases`.
The public v1 renderer remains a separate surface; native preview continues
using `/templates/validate` and `/templates/render`.

Recorded literal validation, invalid-expression validation, literal flagship
rendering against a configured temporary board, unknown-board fallback,
note-array blank geometry and panel blank geometry satisfy the existing
native decoding invariants. `valid` agrees with `errors.isEmpty`; rendered
text equals newline-joined `lines`; `line_count` equals their count. The known
board reports `vestaboard_v1` and an empty charset-issue list. The fallback
reports null charset/charset issues. Optional layers/canvas issues remain
compatible with the native optional-array handling.

This source and fixture evidence supports adding exact non-development
**10.1.7** to the existing validation/preview audit gate, within its existing
input subset. Kit/root own that code decision. This track does not widen any
gate. Real providers, rich pixel layers, actual board transport, native proxy
sessions and all-version compatibility remain unproven.

Verification recorded: Docker replay passed **55 cases** plus generation and
evaluation assertions; the full host contract suite passed **29 tests**.
