import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit
import FiestaBoardRender

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
    @RootState private var stageBoardHeight: CGFloat = 0
    /// The server's variables and functions (iOS-F1, B21/B22/B32), shared with the pickers.
    @StateObject private var catalog = EditorCatalogStore()
    /// Draw on board (iOS-F1, B23).
    @StateObject private var draw = DrawModeController()
    @RootState private var drawMode = false
    /// Text | Canvases (PLAN B24), offered only while the stage shows an LED pixel display.
    @RootState private var editingCanvases = false
    @StateObject private var canvasState = CanvasEditorState()
    @RootState private var canvasScroll = ScrollPosition()
    @RootState private var canvasScrollY: CGFloat = 0

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

    /// Keyboard up: the title and toolbar step aside (the keyboard accessory mirrors the toolbar)
    /// so the board keeps its size and is never covered (B30), on a phone and on iPad.
    private var compactTyping: Bool { isTextInputActive }

    /// iPad portrait, keyboard down (P5): no empty band under the document; the board grows to
    /// its stretch limit and the rows fill the rest.
    private var fillsHeight: Bool { sizeClass == .regular && !compactTyping && !showsCanvases }

    /// The stage's display when it is an LED pixel matrix (PLAN B24).
    private var pixelDisplay: PixelDisplay? { PixelDisplay(model.boards.first { $0.id == model.selectedBoardID }) }
    private var showsCanvases: Bool { editingCanvases && pixelDisplay != nil && model.lines != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reason = saveDisabledReason { saveReason(reason) }
            if drawMode {
                // B23: the rows collapse; the toolbar becomes swatches, eraser and stamps; the board
                // takes the width and paints as you drag.
                title
                DrawModeBar(controller: draw, canUndo: model.canUndo, canRedo: model.canRedo,
                            onUndo: { model.undo(); pipeline.flush() }, onRedo: { model.redo(); pipeline.flush() },
                            onDone: endDrawing)
                stage.padding(.top, 8)
                Spacer(minLength: 0)
            } else {
            if !compactTyping {
                title
                // The toolbar sits directly under the title (B12/B15); the keyboard accessory mirrors it.
                if !showsCanvases { DocumentToolbar(model: model, buffer: buffer, pipeline: pipeline, rich: $rich, slots: drawSlot) }
            }
            StageDocumentLayout(minDocumentWidth: TemplateWorkspaceView.documentWidth(columns: boardCols),
                                minDocumentHeight: TemplateWorkspaceView.documentHeight(rows: min(boardRows, 3)),
                                fillsHeight: fillsHeight) {
                stage
                VStack(alignment: .leading, spacing: 10) {
                    if let notice = model.recoveryNotice { recoveryBanner(notice) }
                    if model.saveStatus.needsAttention { attentionBanner }
                    if pixelDisplay != nil && model.lines != nil { surfacePicker }
                    else if !model.canvases.isEmpty { notPixelNotice }
                    if showsCanvases, let display = pixelDisplay {
                        // W4: a drag that starts on a drawing surface edits it, so a rail beside
                        // the panel scrolls it from anywhere.
                        HStack(alignment: .top, spacing: 6) {
                            ScrollView {
                                CanvasesPanel(model: model, state: canvasState, display: display, gridRows: boardRows, gridCols: boardCols,
                                              onCommitted: { pipeline.edited() })
                                    .padding(.bottom, 12)
                            }
                            .scrollPosition($canvasScroll)
                            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in canvasScrollY = y }
                            .scrollIndicators(.visible)
                            .scrollDismissesKeyboard(.interactively)
                            CanvasScrollRail { delta in canvasScroll.scrollTo(y: max(0, canvasScrollY - delta)) }
                        }
                    } else {
                        TemplateWorkspaceView(model: model, buffer: buffer, pipeline: pipeline,
                                              isTextInputActive: $isTextInputActive, rich: $rich,
                                              onDraw: canDraw ? { startDrawing() } : nil,
                                              charsetIssues: pipeline.state.charsetIssues, fillsHeight: fillsHeight,
                                              maximumDocumentHeight: stageBoardHeight > 0 ? stageBoardHeight : nil)
                    }
                    if let message = model.message, !Self.isRoutineMessage(message) {
                        Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            .accessibilityIdentifier("editorMessage")
                    }
                }
            }
            .padding(.top, compactTyping ? 0 : 8)
            }
        }
        .environmentObject(catalog)
        .animation(.easeInOut(duration: 0.2), value: compactTyping)
        .padding(.horizontal, sizeClass == .compact ? 12 : 16).padding(.top, compactTyping ? 4 : 14).padding(.bottom, 8)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { toastView }
        .preference(key: EditorIsOpenKey.self, value: true)
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
            if model.selectedBoardID == nil,
               let id = EditorBoardChoice.initialChoice(model.boards, remembered: model.rememberedBoardID, rows: boardRows, cols: boardCols) {
                model.chooseBoard(id)
            }
            pipeline.flush()
            await model.checkRecovery()
        }
        .task { await catalog.load(deploymentID: model.identity.deploymentID, isSimulated: model.isSimulated) }
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
    /// "Doesn't fit · 6 × 22" when the chosen display's grid isn't the page's (P1: a Note page
    /// on the Flagship "Kitchen" used to read "3 × 15 · Kitchen" as if it fit).
    private var fitNote: String? {
        guard let board = model.boards.first(where: { $0.id == model.selectedBoardID }),
              board.fits(rows: boardRows, cols: boardCols) == false, let rows = board.rows, let cols = board.cols else { return nil }
        return EditorStrings.doesNotFit(rows: rows, cols: cols)
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

    // MARK: Draw on board (iOS-F1, B23)

    /// Split-flap pages with a cell stage only (LED faces and pixel surfaces have their own canvas).
    private var canDraw: Bool { !isPanel && physicalFrame == nil && pixelDisplay == nil && model.lines != nil && !model.editingFrozen }
    private var drawSlot: AnyView? {
        guard canDraw else { return nil }
        return AnyView(Button(action: startDrawing) {
            Image(systemName: "pencil.tip.crop.circle").frame(width: 34, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(EditorStrings.drawOnBoard).contextMenu { Text(EditorStrings.drawOnBoard) }
        .accessibilityLabel(EditorStrings.drawOnBoard)
        .accessibilityIdentifier("toolbar_draw"))
    }
    private func startDrawing() {
        pipeline.flush()
        buffer.resignFocus()
        draw.cancel()
        drawMode = true
    }
    private func endDrawing() {
        draw.cancel()
        drawMode = false
        pipeline.flush()
    }
    private func commitStroke() {
        guard let stroke = draw.finish(rows: model.lines ?? [], cols: boardCols) else { return }
        model.applyStroke(stroke)
        UIAccessibility.post(notification: .announcement, argument: "Painted \(stroke.paintedRows.count) row\(stroke.paintedRows.count == 1 ? "" : "s")")
    }
    /// While drawing, painted and positional left-aligned rows are drawn locally at once; the
    /// rest keep the server's last render (web `drawPreviewMessage`).
    private var drawStageLines: [String] {
        StrokeTransaction.preview(rows: model.lines ?? [], serverLines: stageLines,
                                  alignment: { model.lineAlignment($0) }, wrap: { model.lineWrap($0) },
                                  pending: draw.pending, brush: draw.brush, boardRows: boardRows, cols: boardCols)
    }

    private var stage: some View {
        PreviewStage(lines: drawMode ? drawStageLines : (pixelDisplay == nil ? stageLines : Self.blankHidden(stageLines, canvasState.canvases(model), rows: boardRows, cols: boardCols)), rows: boardRows, cols: boardCols, isPanel: isPanel, physical: physicalFrame,
                     state: pipeline.state, boards: model.boards, selectedBoardID: model.selectedBoardID,
                     fitNote: fitNote, footnote: stageFootnote, disabled: model.editingFrozen,
                     onChooseBoard: { model.chooseBoard($0) }, onRetry: { pipeline.retry() }, onRefresh: { pipeline.flush() },
                     geometry: model.pageGeometry,
                     onChooseGeometry: { shape in pipeline.flush(); model.setGeometry(shape); pipeline.flush() },
                     animated: !drawMode,
                     drawOverlay: drawMode ? { size, displayModel, stretch in
                         AnyView(DrawCanvasOverlay(size: size, model: displayModel, stretch: stretch, controller: draw, onCommit: commitStroke))
                     } : nil,
                     led: pixelDisplay?.model, layers: stageLayers,
                     ledMaxHeight: showsCanvases && sizeClass == .compact ? 200 : 320,
                     onBoardHeightChange: { stageBoardHeight = $0 })
            .overlay(alignment: .bottomTrailing) { stageLayerProbe }
            #if DEBUG
            .overlay(alignment: .topTrailing) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Preview input latency")
                    .accessibilityIdentifier("previewInputLatency")
                    .accessibilityValue(pipeline.state.inputToPreviewSeconds.map { String($0) } ?? "pending")
            }
            #endif
    }

    // MARK: Canvases (PLAN B24)

    /// Text under a `hide` canvas is blank on the board (`covered_cells`); plain rows are blanked
    /// here too, so the local drawing matches (markup rows are left to the server).
    static func blankHidden(_ lines: [String], _ canvases: [LegacyCanvas], rows: Int, cols: Int) -> [String] {
        let hidden = CanvasRaster.hiddenCells(canvases, rows: rows, cols: cols)
        guard !hidden.isEmpty else { return lines }
        return lines.enumerated().map { r, line in
            guard !line.contains("{") else { return line }
            return String(line.enumerated().map { c, ch in hidden.contains([r, c]) ? " " : ch })
        }
    }

    /// The canvases on the stage: the server's layers when its render is current, else the editor's
    /// own drawing of the committed (or in-gesture) canvases, so painting and dragging show at once.
    private var stageLayers: [PixelLayer] {
        guard let display = pixelDisplay else { return [] }
        if canvasState.live == nil, !model.previewStale, pipeline.state.lines != nil,
           let preview = model.lastPreview, !preview.isSimulated, !preview.layers.isEmpty {
            return preview.layers.compactMap { layer in
                Data(base64Encoded: layer.rgba).map { PixelLayer(x: layer.x, y: layer.y, w: layer.width, h: layer.height, rgba: $0) }
            }
        }
        return display.layers(canvasState.canvases(model))
    }
    /// A test hook: the layers' lit-pixel count and bounds, so UI tests see the stage change.
    private var stageLayerProbe: some View {
        let layers = pixelDisplay == nil ? [] : stageLayers
        var lit = 0
        for layer in layers { var i = 3; while i < layer.rgba.count { if layer.rgba[i] > 0 { lit += 1 }; i += 4 } }
        return Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("Canvas layers")
            .accessibilityValue("\(layers.count) layers, \(lit) lit")
            .accessibilityIdentifier("stageCanvasLayers")
    }

    private var surfacePicker: some View {
        Picker(CanvasStrings.editingSurface, selection: Binding(get: { editingCanvases }, set: { canvases in
            pipeline.flush(); buffer.resignFocus(); editingCanvases = canvases
        })) {
            Text(CanvasStrings.text).tag(false)
            Text(CanvasStrings.canvases).tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .disabled(model.editingFrozen)
        .accessibilityIdentifier("editingSurface")
    }

    private var notPixelNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "square.grid.3x3.square").foregroundStyle(.secondary)
            Text(CanvasStrings.notPixelNotice).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canvasNotPixelNotice")
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
            // W4: the automatic checkpoint (B25) now holds the accepted revision, so reopening the
            // saved page offers no stale pre-save draft (the model leaves this to its caller).
            await model.saveDraft()
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
    /// Stacked layout only: the document takes all the height under the board (P5, iPad
    /// portrait), instead of hugging its rows.
    var fillsHeight = false

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
            // Never taller than the room above the keyboard: the board scales down instead (B30).
            let stageHeight = min(stage.sizeThatFits(ProposedViewSize(width: stageWidth, height: nil)).height, bounds.height)
            stage.place(at: CGPoint(x: bounds.minX + documentWidth + spacing, y: bounds.minY),
                        proposal: ProposedViewSize(width: stageWidth, height: stageHeight))
        } else {
            // The stage keeps its full size; the document gives way down to ~3 rows (B30), and only
            // then does the board scale down.
            var stageHeight = max(0, min(stage.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height,
                                         bounds.height - minDocumentHeight - spacing, bounds.height * 0.75))
            // Free space under the document (keyboard up, iPad portrait) goes to the board: its
            // tiles grow taller, up to `StageBoard.maxStretch` (P1). The board stays the largest
            // element and is never covered.
            let documentNatural = document.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            let spare = bounds.height - stageHeight - spacing - documentNatural
            if spare > 1 {
                stageHeight = stage.sizeThatFits(ProposedViewSize(width: bounds.width, height: stageHeight + spare)).height
            }
            stage.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: stageHeight))
            let room = max(0, bounds.height - stageHeight - spacing)
            let documentHeight = fillsHeight ? room : min(document.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height, room)
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

/// The canvases panel's scroll rail (W4): a strip with a grip, beside the area grid, pixel pad and
/// shapes surface, where a drag always scrolls (those surfaces take drags that start on them).
struct CanvasScrollRail: View {
    /// The finger's vertical travel since the last change (content follows the finger).
    var onScroll: (CGFloat) -> Void
    @State private var last: CGFloat = 0
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(uiColor: .tertiarySystemFill))
            .overlay(alignment: .top) {
                VStack(spacing: 3) {
                    Image(systemName: "chevron.up")
                    Image(systemName: "line.3.horizontal")
                    Image(systemName: "chevron.down")
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 10)
            }
            .frame(width: 22)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in onScroll(value.translation.height - last); last = value.translation.height }
                .onEnded { _ in last = 0 })
            .accessibilityElement()
            .accessibilityLabel(CanvasStrings.scrollRail)
            .accessibilityIdentifier("canvasesPanelHandle")
    }
}
