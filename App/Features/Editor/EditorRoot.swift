import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit

private typealias RootState<Value> = SwiftUI.State<Value>

/// Mount point of the document editor for legacy template pages (PLAN §1.1, §3.2–3.3): the page
/// title, the pinned live board, and one board-shaped document. One Save, one status word.
@MainActor
struct EditorRoot: View {
    @ObservedObject var model: LocalPageEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var buffer: DocumentBuffer
    @StateObject private var pipeline: PreviewPipeline
    @RootState private var isTextInputActive = false
    /// Rich | Plain persists across launches (PLAN B18).
    @AppStorage("editor.richMode") private var rich = true
    @RootState private var confirmClose = false
    @RootState private var confirmReload = false
    @RootState private var showDetails = false
    @RootState private var confirmResize = false
    @RootState private var toast: String?
    @RootState private var titleDraft = ""
    @RootState private var started = false

    init(model: LocalPageEditorModel) {
        self.model = model
        let buffer = DocumentBuffer()
        _buffer = StateObject(wrappedValue: buffer)
        _pipeline = StateObject(wrappedValue: PreviewPipeline(
            commit: { [weak model, weak buffer] in
                guard let model, let buffer, buffer.isDirty else { return }
                if buffer.plainMode { model.commitPlainRows(buffer.rows) } else { model.commitRows(buffer.rows) }
                buffer.markCommitted()
                model.scheduleDraftSave()
            },
            render: { [weak model] in try await model?.renderStage() ?? .local }))
    }

    private var geometry: TemplateGeometry? { model.authoringGeometry }
    private var boardRows: Int { geometry?.rows ?? 6 }
    private var boardCols: Int { geometry?.columns ?? 22 }
    private var isPanel: Bool { geometry?.isPanel ?? false }

    /// Phone with the keyboard up: the title and toolbar step aside (the keyboard accessory
    /// mirrors the toolbar) so the board keeps its full size above the rows (B30).
    private var compactTyping: Bool { sizeClass == .compact && isTextInputActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reason = saveDisabledReason { saveReason(reason) }
            if !compactTyping {
                title
                // The toolbar sits directly under the title (B12/B15); the keyboard accessory mirrors it.
                DocumentToolbar(model: model, buffer: buffer, pipeline: pipeline, rich: $rich)
            }
            StageDocumentLayout(minDocumentWidth: TemplateWorkspaceView.documentWidth(columns: boardCols),
                                minDocumentHeight: TemplateWorkspaceView.documentHeight(rows: min(boardRows, 3))) {
                stage
                VStack(alignment: .leading, spacing: 10) {
                    if let notice = model.recoveryNotice { recoveryBanner(notice) }
                    if model.saveStatus.needsAttention { attentionBanner }
                    TemplateWorkspaceView(model: model, buffer: buffer, pipeline: pipeline,
                                          isTextInputActive: $isTextInputActive, rich: $rich)
                    if let message = model.message, !Self.isRoutineMessage(message) {
                        Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            .accessibilityIdentifier("editorMessage")
                    }
                }
            }
            .padding(.top, compactTyping ? 0 : 8)
        }
        .animation(.easeInOut(duration: 0.2), value: compactTyping)
        .padding(.horizontal, sizeClass == .compact ? 12 : 16).padding(.top, compactTyping ? 4 : 14).padding(.bottom, 8)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { toastView }
        .navigationTitle(EditorStrings.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.hasServerChanges || buffer.isDirty || model.isSaving || model.editingFrozen || isTextInputActive)
        .toolbar { toolbar }
        .confirmationDialog(EditorStrings.discardTitle, isPresented: $confirmClose, titleVisibility: .visible) {
            Button(EditorStrings.discardAndLeave, role: .destructive) { leave() }
            Button(EditorStrings.keepEditing, role: .cancel) {}
        } message: { Text(EditorStrings.discardMessage) }
        .confirmationDialog(EditorStrings.reloadTitle, isPresented: $confirmReload, titleVisibility: .visible) {
            Button(EditorStrings.reloadAction, role: .destructive) { Task { await model.reloadComparedRemote() } }
            Button(EditorStrings.keepLocalWork, role: .cancel) {}
        } message: { Text(EditorStrings.reloadMessage) }
        .sheet(isPresented: $showDetails) { DocumentDetailsSheet(model: model) }
        .confirmationDialog(EditorStrings.resizeTitle, isPresented: $confirmResize, titleVisibility: .visible) {
            Button(EditorStrings.resizeAndSave, role: .destructive) { save(confirmedResize: true) }
                .accessibilityIdentifier("resizeAndSave")
            Button(EditorStrings.keepEditing, role: .cancel) {}
        } message: { Text(EditorStrings.resizeMessage) }
        .task {
            guard !started else { return }
            started = true
            titleDraft = model.name
            if model.selectedBoardID == nil, let id = model.rememberedBoardID ?? model.boards.first?.id { model.chooseBoard(id) }
            pipeline.flush()
            await model.checkRecovery()
        }
        .onChange(of: model.name) { _, name in if name != titleDraft { titleDraft = name } }
        .onChange(of: model.selectedBoardID) { _, _ in pipeline.targetChanged() }
        // Recovery, reload or a save changed the session on its own: show its render.
        .onChange(of: model.documentRevision) { _, _ in
            if !buffer.isDirty && !pipeline.hasPendingCommit && !pipeline.state.isUpdating { pipeline.flush() }
        }
        .onChange(of: model.remoteStatus) { _, status in if status == .comparison { confirmReload = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pipeline.flush(); Task { await model.checkpointNow() } }
        }
    }

    /// Automatic checkpoints and undo echoes are not news; errors, conflicts and reloads are.
    static func isRoutineMessage(_ message: String) -> Bool {
        message.hasPrefix("Local draft saved") || message.hasPrefix("Undid") || message.hasPrefix("Redid")
    }

    // MARK: Title

    private var title: some View {
        TextField(EditorStrings.titlePlaceholder, text: $titleDraft)
            .font(.largeTitle.weight(.bold))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .disabled(model.editingFrozen)
            .onChange(of: titleDraft) { _, value in
                let trimmed = value.unicodeScalars.count
                if (1...100).contains(trimmed), value != model.name { pipeline.flush(); model.setName(value) }
            }
            .accessibilityLabel(EditorStrings.titleLabel)
            .accessibilityIdentifier("pageTitle")
    }

    // MARK: Stage

    /// The server's render when there is one; otherwise (no display, empty document, or the
    /// demo service, which echoes rows unrendered) the local projection of the *committed* rows,
    /// so the stage follows the same 250 ms commit cadence either way.
    private var stageLines: [String] {
        if let lines = pipeline.state.lines, model.lastPreview?.isSimulated != true { return lines }
        var rows = model.lines ?? []
        // The demo has no server to work out values: show the sample values, never token names.
        if model.isSimulated { rows = SampleValues.resolve(rows, catalog: .sample(authoritative: true)) }
        return LocalStageProjection.lines(rows: rows, alignment: { model.lineAlignment($0) },
                                          boardRows: boardRows, cols: boardCols, uppercase: !isPanel)
    }
    private var hasDynamicTokens: Bool {
        (model.lines ?? []).contains { row in TemplateSyntax.fragments(row).contains { $0.kind == .expression || $0.kind == .formula } }
    }
    private var physicalFrame: PhysicalPreviewFrame? {
        guard pipeline.state.lines != nil, case .physical(let frame) = model.lastPreview?.surface else { return nil }
        return frame
    }
    /// Plain and short, and only when it explains something on the board.
    private var stageFootnote: String? {
        guard hasDynamicTokens, !compactTyping else { return nil }
        if model.isSimulated { return EditorStrings.sampleValuesNote }
        if model.selectedBoardID == nil { return EditorStrings.chooseDisplayNote }
        return nil
    }

    /// Why Save is off, shown beside it whenever there is something to save (E1 open issue 4).
    private var saveDisabledReason: String? {
        guard model.hasServerChanges || buffer.isDirty, !model.isSaving, !model.editingFrozen,
              let reason = model.serverSaveDisabledReason, model.saveStatus != .conflict, model.saveStatus != .unknown else { return nil }
        return reason
    }
    private func saveReason(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(EditorStrings.saveOff(reason)).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saveDisabledReason")
    }

    private var stage: some View {
        PreviewStage(lines: stageLines, rows: boardRows, cols: boardCols, isPanel: isPanel, physical: physicalFrame,
                     state: pipeline.state, boards: model.boards, selectedBoardID: model.selectedBoardID,
                     fitNote: nil, footnote: stageFootnote, disabled: model.editingFrozen,
                     onChooseBoard: { model.chooseBoard($0) }, onRetry: { pipeline.retry() }, onRefresh: { pipeline.flush() },
                     geometry: model.pageGeometry,
                     onChooseGeometry: { shape in pipeline.flush(); model.setGeometry(shape); pipeline.flush() })
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(EditorStrings.close) { close() }.disabled(model.isSaving || model.editingFrozen)
        }
        // The page name is the title on screen; the bar's centre carries the one status word,
        // so "Edit Page" never truncates to "Ed…" beside the buttons (it stays the bar's name).
        ToolbarItem(placement: .principal) {
            SaveStatusChip(status: buffer.isDirty && model.saveStatus == .saved ? .unsaved : model.saveStatus)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(EditorStrings.documentDetails, systemImage: "info.circle") { pipeline.flush(); showDetails = true }
                .labelStyle(.iconOnly).accessibilityIdentifier("documentDetails")
            Button(EditorStrings.save) { save() }
                .bold()
                .disabled(!(model.canSaveToServer || (buffer.isDirty && model.serverSaveDisabledReason == nil)) || model.editingFrozen)
                .accessibilityHint(saveDisabledReason ?? "")
                .accessibilityIdentifier("savePageOnServer")
        }
    }

    // MARK: Banners

    private func recoveryBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
            Text(model.hasCorruptDraft ? "Damaged local draft found" : "Local draft available")
                .font(.footnote.weight(.semibold)).lineLimit(1)
                .accessibilityHint(notice)
            Spacer(minLength: 4)
            if model.canRecover { Button("Recover local draft") { pipeline.flush(); model.recoverDraft() } }
            if model.hasCorruptDraft { Button("Preserve damaged draft separately") { Task { await model.preserveCorruptDraft() } } }
            else { Button("Keep fetched page") { model.dismissRecovery() } }
        }
        .font(.footnote).buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recoveryBanner")
    }

    private var attentionBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
            Text(model.saveStatus == .unknown ? EditorStrings.unknownBanner : EditorStrings.conflictBanner).font(.footnote)
            Spacer(minLength: 4)
            Button(EditorStrings.compareAndReload) {
                pipeline.flush()
                if model.remoteStatus == .comparison { confirmReload = true } else { Task { await model.fetchRemoteComparison() } }
            }
            .font(.footnote.weight(.semibold)).buttonStyle(.borderedProminent).tint(.red)
            .disabled(!model.canFetchRemote && model.remoteStatus != .comparison)
            .accessibilityIdentifier("compareAndReload")
        }
        .padding(10)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveAttentionBanner")
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("editorToast")
        }
    }

    // MARK: Actions

    private func close() {
        pipeline.flush()
        buffer.resignFocus()
        if model.hasServerChanges { confirmClose = true } else { leave(checkpoint: false) }
    }
    private func leave(checkpoint: Bool = false) {
        pipeline.cancel()
        model.cancelScheduledDraftSave()
        model.endEditingSession()
        dismiss()
    }
    private func save(confirmedResize: Bool = false) {
        pipeline.flush()
        buffer.resignFocus()
        guard model.canSaveToServer else { return }
        // B28: shrinking a saved page's board asks first.
        if model.geometryShrinks && !confirmedResize { confirmResize = true; return }
        Task {
            await model.saveToServer()
            guard model.remoteStatus == .idle, !model.hasServerChanges else { return }
            toast = model.isSimulated ? EditorStrings.pageUpdatedSimulated : EditorStrings.pageUpdated
            UIAccessibility.post(notification: .announcement, argument: toast)
            try? await Task.sleep(for: .milliseconds(1500))
            leave()
        }
    }
}

/// Stage and document column (PLAN B12/B33): on a narrow width the board is pinned above the
/// document; on a wide one (iPad landscape, large windows: ≥ 860 pt) it sits beside it, document
/// on the left with room for a full board row (≥ 400 pt), so rows never soft-wrap early. A single
/// layout keeps the document's text view (and its selection) alive across size changes.
struct StageDocumentLayout: Layout {
    static let wideWidth: CGFloat = 860
    /// The document column's natural width (its board-width row plus gutter); the stage gets the rest.
    var minDocumentWidth: CGFloat = 320
    /// The document never shrinks below about three rows, so the caret row stays in view.
    var minDocumentHeight: CGFloat = 96
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 400, height: 600))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let stage = subviews[0], document = subviews[1]
        if bounds.width >= Self.wideWidth {
            // The board is the largest element: the document takes its natural width, at most 42%.
            let documentWidth = min(max(minDocumentWidth, 300), ((bounds.width - spacing) * 0.42).rounded())
            let stageWidth = bounds.width - spacing - documentWidth
            let documentHeight = min(document.sizeThatFits(ProposedViewSize(width: documentWidth, height: nil)).height, bounds.height)
            document.place(at: bounds.origin, proposal: ProposedViewSize(width: documentWidth, height: documentHeight))
            stage.place(at: CGPoint(x: bounds.minX + documentWidth + spacing, y: bounds.minY),
                        proposal: ProposedViewSize(width: stageWidth, height: nil))
        } else {
            // The stage keeps its full size; the document gives way down to ~3 rows (B30), and only
            // then does the board scale down.
            let stageHeight = max(0, min(stage.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height,
                                         bounds.height - minDocumentHeight - spacing, bounds.height * 0.75))
            stage.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: stageHeight))
            let room = max(0, bounds.height - stageHeight - spacing)
            let documentHeight = min(document.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height, room)
            document.place(at: CGPoint(x: bounds.minX, y: bounds.minY + stageHeight + spacing),
                           proposal: ProposedViewSize(width: bounds.width, height: documentHeight))
        }
    }
}

/// Raw JSON, server comparison and the full evaluation result, behind ⓘ (PLAN B25).
struct DocumentDetailsSheet: View {
    @ObservedObject var model: LocalPageEditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    LabeledContent("Server", value: model.serverSnapshotStatus)
                    LabeledContent("Local recovery copy", value: model.hasUnsavedChanges ? "Pending" : "Up to date")
                    if let reason = model.serverSaveDisabledReason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Current local document · select to copy") {
                    Text(model.readOnlyDocumentText).font(.caption.monospaced()).textSelection(.enabled)
                }
                Section("Server page") {
                    Button("Fetch server page for comparison") { Task { await model.fetchRemoteComparison() } }
                        .disabled(!model.canFetchRemote)
                    if let comparison = model.remoteComparisonText {
                        Text(comparison).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if let preview = model.lastPreview {
                    Section("Latest preview") {
                        Text(preview.isSimulated ? "Demo preview · simulated" : "Server preview").font(.caption)
                        if let charset = preview.charset { LabeledContent("Character set", value: charset) }
                        LabeledContent("Character warnings", value: "\(preview.charsetIssueCount)")
                        LabeledContent("Canvas warnings", value: "\(preview.canvasIssueCount)")
                        Text(String(decoding: preview.rawData, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(EditorStrings.documentDetails).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("documentDetailsSheet")
    }
}
