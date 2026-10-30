# FiestaBoardEditorState

MainActor/Combine editor coordination, host tested on macOS. Depends on Documents and Kit; the document value model remains independent of networking and AppState.

The app injects actions bound to one BoardStore page/session context. Empty local templates can be edited; server saving requires at least one row. Structural and formatting edits invalidate evaluation results and use document undo/recovery. A server save checkpoints the captured local draft before the request, freezes editing until completion, and sends only changed name, template lines, and line metadata with the recovered/loaded baseline revision. Acknowledgement adopts the returned document and clears undo/redo. It does not claim that the pre-request local file contains the new server revision.

Conflict and uncertain outcomes preserve local work and block resends. An explicit scoped readback displays a comparison without advancing the baseline. Confirmed reload first preserves the current draft, then adopts the compared page and clears history. There is no automatic merge, rebase, resend, or direct board delivery. Full local JSON remains selectable for copying.

Evaluation uses the current raw document and an explicitly chosen immutable board. Document revision, board identity, and request generation suppress late results. Demo results are literal simulations; visual layers are reported as unsupported in the text preview.

Normal local checkpoints are explicit. Authentication/session loss during evaluation or readback is a bounded recovery exception: the latest deliberate local content is preserved without advancing the explicit local-save checkpoint. Exact document-content barriers established by explicit save/recovery or acknowledged/confirmed server adoption prevent a late error from overwriting the prior draft with reloaded server content. Document-context invalidation (`stalePageContext`) is distinct from connection loss and never triggers this exception. The view must call `endEditingSession()` on an explicit Close or Discard decision so a late callback cannot resurrect discarded edits.
