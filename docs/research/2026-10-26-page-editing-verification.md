# Page saving and preview draft verification

Native product commit `aa03da7` passed Astra specification and quality review after correcting one recovery-data-loss race. Backend protocol commit `dadbc191e7b329a2803f229dcca22914e6a83b6e` separately passed Astra review and is pushed on `Fiestaboard/FiestaBoard:codex/ios-api-access`.

## Available to try

In Demo, open Library → a template page → Edit page. Change the name or an existing raw template line. Save locally, or choose the simulated server save and review its confirmation. Choose a board and explicitly validate/preview. Demo output is literal/simulated; it does not evaluate plugin variables or formulas.

Settings can simulate rejected/unknown results. The editor preserves local work, blocks repeated saves and provides an explicit server comparison followed by a confirmed reload. It does not merge, rebase or replay automatically. A successful page save acknowledges stored content; it does not claim hardware delivery.

Live page saves require explicit session opt-in plus an original revision and the exact advertised `page-revision-v1` protocol on a supported template page. Unpatched servers remain save-disabled. This feature gate is separate from the existing 10.0.0 board-control gate. Validation/render adapters currently accept non-development 10.0.0/10.1.2; unknown internal-API versions refuse locally. No backend deployment was performed.

## Verification

| Check | Result |
| --- | --- |
| Kit host tests | 42 passed |
| AppState host tests | 35 passed |
| Documents host tests | 25 passed |
| EditorState host tests | 15 passed |
| Contract-tool tests and integrity | 25 passed; integrity passed |
| Final Simulator and iPhone builds | Unsigned builds succeeded |
| UI test target | Build-for-testing succeeded; seven tests compiled, none executed |
| Backend protocol tests | 522 focused/contract tests passed; Astra independently ran 75 |
| Independent native review | Original failing recovery reproduction passes unchanged; no open findings in the bounded wave |

The final native build logs contain no Swift source diagnostics. AppIntents metadata notices and inaccessible CoreSimulator-service messages are environment limitations, not runtime-test evidence. Physical-device signing/install, visual inspection, IME/selection, accessibility and window/pose interaction still need manual QA using [the testing guide](../draft-testing.md).

## Recovery guarantees and limits

Page-document context replacement is distinct from authentication/session loss. Stale previews and cancelled evaluations cannot silently overwrite the draft preserved before a reload. Emergency recovery writes on actual connection loss require new local content and do not mark the explicit local checkpoint clean. Explicit Close/Discard suppresses late recovery writes. Successful server adoption clears undo history so it cannot restore an obsolete base revision.

Only changed supported name/fixed-slot template fields are sent. The local tree preserves exact Unicode, number lexemes, nulls and unknown content. Backend typed pages do not promise arbitrary unknown on-disk-field preservation. Rich/structural/canvas authoring, visual layer rendering, create/delete/duplicate, deliberate merge/rebase and full web parity remain unfinished.

The backend branch is reviewed and pushed, and [draft PR #2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373) is now open. It was created with `gh` at the user's direction after the connector blocked creation. [The prepared PR description and comparison link](2026-10-25-backend-pr-draft.md) remain available. Sol 6.1 implemented this wave; Astra reviewed it. Claude CLI authentication remained unavailable from the earlier expired-token attempts, so no Opus contribution is claimed.
