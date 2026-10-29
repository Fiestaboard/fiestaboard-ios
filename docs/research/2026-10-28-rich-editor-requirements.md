# Split-flap and LED rich-editor acceptance

User priority: October28 approval explicitly requires rich editing for **both split-flap and LED**. This is a binding implementation/acceptance matrix for W4/W5, not a claim of delivered rich editing. Current native editing remains the bounded fixed-slot raw-template draft until the implementation lands.

## Current source distinction

Source10.1.17 `b5eac069dce10945eac61e1fdadf6ee4a903ba08` has two rich paths. `web/src/components/tiptap-template-editor/TipTapTemplateEditor.tsx` and its serialization/extensions implement the app's split-flap authoring. `web/src/components/charset-template-editor.tsx` wraps FiestaUI's TemplateEditor for LED/output-plugin/panel charsets. The latter explicitly supports source-capability-dependent color spans (`{{red:HOT}}`), block spans (`{{black/white:OPEN}}`), icons (`{{icon:sun}}`), mixed case and unsupported-cell marking. The selected charset controls which tools are offered. Reusing only split-flap token assumptions cannot satisfy LED parity.

Current source pins FiestaUI @fiestaboard/ui 8.14.2, registry tarball https://registry.npmjs.org/@fiestaboard/ui/-/ui-8.14.2.tgz, integrity `sha512-3IdmRrCZ6K4hsgSMW5ARgUtssdfL/lZxKvexLoztKWNNwmCkeGQ0S1IilBz/rL5nDrLwtYW5D9dVfdDAFayq1g==`. Verify that exact dependency when building shared golden fixtures. Review package source and license before deriving behavior or borrowing assets. Do not infer local compatibility merely because both upstream paths are named rich editors.

## Required independent matrix

| Area | Split-flap evidence | LED evidence |
| --- | --- | --- |
| Source round trip | text/color tiles, fill-space, variable/formula nodes and markup preserved | spans/block spans/icons/mixed-case/charset-specific markup preserved |
| Toolbar capabilities | supported palette/glyph/tile/draw/token tools only | supported charset color/text/block/icon tools only; unavailable capabilities explained |
| Structure | insert/remove/reorder lines, alignment/wrap and geometry constraints | same source-supported structure plus correct span extents and case/charset behavior |
| Rich/plain switch | canonical round trips without normalization damage or unknown-field loss | no flattening of spans/block colors/icons into flap or raw-only presentation |
| Native text input | caret/selection, token-adjacent edits, multiline paste, IME/dictation, scalar-distinct Unicode | identical input matrix with token/span boundaries, mixed case and unsupported glyphs |
| Undo/redo | semantic groups preserve document/selection and supported brush operations | semantic span/icon/format groups preserve content/selection |
| Preview | exact target glyph/color/geometry and server warnings, including code62/filled71 | exact target spans/icons/visual cells/layers and warnings, using server-authoritative evaluation |
| Save/conflict | original page revision/document protocol, omitted/null and unknown fields | same original-revision contract without stripping rich LED fields |
| Recovery | fresh/existing document, resize/background/auth loss, explicit comparison/adoption | same matrix including pending span edits and pre-adoption copies |
| Accessibility/layout | readable cells/tokens, VoiceOver/keyboard alternatives, large type and compact/expanded layouts | meaningful span/icon/color labels and equivalent accessible editing across layouts |

Target changes must preserve content or explain incompatible representation; they may not silently coerce one family into the other. Live output remains explicitly separate from side-effect-free preview. Stage server/AI changes for review and retain original revisions. Server rasterization/evaluation remains authoritative; native UI does not reimplement providers or template evaluation.

The feasibility milestone passes only after both fixture families satisfy document/IME/undo/round-trip tests and both native rich views actually execute. Renderer visual/device proof is recorded independently for each. Unsupported future content is preserved or editing is blocked with a reason. If TextKit cannot maintain these invariants, record the failed proof and select a reviewed native bridge/model before broad implementation; raw-only LED is not a release compromise.
