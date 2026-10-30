# Native creative editor — next implementation milestone

Builds on the approved native parity plan and rich-editor requirements. User explicitly asks continued implementation with iOS creative-app patterns; no new approval gate. This milestone is useful authoring, not full web parity.

Design: canvas-first, native contextual controls, row selection and editable rich tokens. Compact layouts stack canvas and row inspector; wide windows show them beside each other. Standard iOS toolbars adopt system glass. Keep source editing as an explicit alternative. Preserve original token spelling, unknown document fields, original revision, and draft/conflict safeguards. Dynamic values are placeholders until server evaluation, never invented live values.

Alternatives considered: embedding the whole web editor would deliver familiarity but not native interaction; painting a static board atop a raw form would not deliver meaningful editing. Use native TextKit token attachments with reversible source mapping and SwiftUI canvas/inspector. Preserve unknown syntax as source, not guessed transformations.

## Task 1 — document structure and safe storage
Allow empty templates; add/duplicate/remove/move rows and edit alignment/wrap atomically with their metadata. Carry unknown metadata/number lexemes exactly. Expose model actions, history and metadata projection. Extend partial storage only where audited server contract supports it; unknown/revision safety unchanged. Test source structure/history/recovery/transport.

## Task 2 — native rich editing and canvas
Lossless lexical tokens for flap colors, fill-space, variables/formulas, LED spans and icons. Native rich/source switching, caret insertion, token editing and plain-source clipboard. Canvas clearly labeled design view; no false dynamic preview. Geometry from document. Compact/expanded adaptive inspector, line management, palette and expression entry. Keep inaccessible/future shapes read-only. Test lexical identity and real simulator authoring flows.

## Task 3 — independent review and delivery
Astra review fixes, package tests, iPhone/iPad runtime verification and unsigned device build. Update durable remaining checklist with explicit unproven IME/dictation/pencil/renderer parity. Integrate into main only preserving the user's signing overlay.

Apple guidance checked 2026-10-29: https://developer.apple.com/design/human-interface-guidelines/toolbars and https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass — standard contextual controls, uncluttered groups, content separated from controls.
