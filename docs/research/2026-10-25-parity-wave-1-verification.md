# Controls and local-editor draft verification

Reviewed code: `be72a11` on `codex/ios-foundation`. Astra approved the bounded specification and code quality with no remaining findings after two corrections: exact Unicode comparisons throughout the document/draft pipeline, and visible pending/outcome/readback feedback on Board controls.

## Available to try

- Home → Board controls: pause/resume, schedule following, automatic restore, fallback page, and restore, with captured board/server confirmation and explicit outcome/readback feedback.
- Library → page → Edit local draft: page name and existing raw template lines, undo/redo, explicit on-device save/recovery, and unsaved-close protection.
- Exact JSON numbers, nulls, Unicode sequences and unknown fields are retained. Structural line edits and unsupported content remain restricted rather than converted.

Demo board actions are simulated; saved drafts are real on-device files. Remote page publishing is still disabled pending the reviewed backend protocol and native integration. Only the existing exact 10.0.0 opted-in candidate server supports live board writes; other versions remain read-only.

## Evidence

| Check | Result |
| --- | --- |
| FiestaBoardKit host tests | 29 passed |
| FiestaBoardAppState host tests | 23 passed |
| FiestaBoardDocuments host tests | 22 passed, including 8 Unicode regressions |
| Contract integrity | Passed; separate release-readiness gate remains unmet |
| Generic Simulator app | Unsigned build succeeded |
| Generic iPhone app | Unsigned build succeeded |
| UI test target | Build-for-testing succeeded; tests **not executed** |
| Astra review | Both initial P2 findings closed at `be72a11` |

The final native builds contain no Swift source diagnostics. CoreSimulator access remains unavailable from the managed agent environment. Physical device deployment, visual inspection, resizing, accessibility and TextKit/IME interactions therefore still require the manual checks in [the testing guide](../draft-testing.md).

## Remaining limits

This is a local raw-template editor foundation. Rich token/cell editing, structural template operations, canvas tools, previews and server saves remain unfinished. Local draft saves are explicit, not autosaves across process termination; simultaneous windows currently use the last explicit local save. Full web parity and App Store readiness are not claimed.

Sol 6.1 agents implemented the changes and Astra independently reviewed them. Two actual Claude Opus CLI attempts failed with an expired OAuth token before producing output; no Opus implementation contribution is claimed. The user can refresh Claude's login separately; no credentials were modified by this work.
