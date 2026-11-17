import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardRender

struct ComposeEditor: View {
    @ObservedObject var session: ComposeSession
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    let verifyTarget: (String, ComposeSession) async -> Void
    @State private var preparing = false
    @State private var notice: String?
    @State private var savingPage = false
    @State private var choosingEnd = false
    @State private var end = Date().addingTimeInterval(3600)
    @State private var silenceConfirmation = false
    @State private var picker: ComposePicker?
    @State private var catalog: TemplateCatalog?
    @State private var functions: FunctionCatalog?
    @State private var sentActionID: UUID?
    @State private var sentRevision: UInt64?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var appearance
    private var descriptor: ComposeBufferTarget? { session.bufferedTargetPresentation ?? session.scope.presentation }
    private var name: String { descriptor?.name ?? "Choose a display" }
    private var live: Bool { session.online && session.scope.verifiedOnline }
    private var locked: Bool { preparing || store.commandBusy }
    private var empty: Bool { session.input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var drawing: BoardDrawing? {
        if live, store.board?.summary.id == session.scope.target.boardID { return store.board?.drawing }
        return descriptor?.drawingData.flatMap { try? JSONDecoder().decode(BoardDrawing.self, from: $0) }
    }
    private var tools: ComposeTools { .init(drawing: live ? drawing : nil) }
    private var selectedLine: ComposeBufferLine {
        let prefix = (session.input.text as NSString).substring(to: min(session.input.text.utf16.count, max(0, session.input.selection.lowerUTF16)))
        let row = prefix.components(separatedBy: "\n").count - 1
        return row < session.input.lineMetadata.count ? session.input.lineMetadata[row] : .init()
    }
    private var projection: ComposePreviewProjection? {
        guard let preview = session.preview, let descriptor else { return nil }
        return try? .init(preview: preview, summary: .init(deviceType: descriptor.deviceType,
            rows: descriptor.rows, cols: descriptor.cols, deviceModel: descriptor.deviceModel,
            charset: descriptor.charset), drawing: drawing)
    }
    private var silence: HomeSilencePresentation? {
        guard live, store.selectedBoardID == session.scope.target.boardID else { return nil }
        return HomeSilencePresentation.make(status: status.selectedSilence, boardID: session.scope.target.boardID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionNotice
                    #if DEBUG && canImport(ScreenCaptureKit)
                    ComposeCaptureProbeControls()
                    #endif
                    if let silence {
                        Label(silence.endsAt.map { "Silence is active until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Silence is active", systemImage: "moon")
                            .font(.callout).foregroundStyle(ShellPalette(appearance: appearance).info)
                    }
                    ComposePreviewPanel(projection: projection,
                        notice: .init(diagnosticsData: session.preview?.rawData, stale: session.previewIsStale, online: live),
                        displayName: name, updating: session.previewIsUpdating, retry: session.retryPreview)
                        .figmaNode("compose:preview", label: "Message preview")
                    ComposeTextView(input: session.input, enabled: !locked, onChange: edit)
                        .frame(minHeight: 150)
                        .background(ShellPalette(appearance: appearance).card, in: RoundedRectangle(cornerRadius: 12))
                        .figmaNode("compose:source", label: session.input.text)
                    if let drawing, drawing.isKnownDevice, drawing.technology == "led_matrix" {
                        Text("\(drawing.pixelWidth ?? 0) × \(drawing.pixelHeight ?? 0) px · \(drawing.font ?? "") font")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { durationMenu; silenceMenu }
                        VStack(alignment: .leading, spacing: 12) { durationMenu; silenceMenu }
                    }
                    if let notice { Text(notice).font(.callout).accessibilityIdentifier("composeDraftNotice") }
                    outcome
                }
                .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ShellPalette(appearance: appearance).background)
            .navigationTitle("Compose").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await close() } }
                        .disabled(preparing).accessibilityIdentifier("composeCancel")
                }
                ToolbarItem(placement: .principal) { displayMenu }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show now") {
                        if silence != nil { silenceConfirmation = true } else { Task { await send() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(locked || empty || !live || !store.canPerformCompose)
                    .accessibilityIdentifier("composeShowNow")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { capabilityToolbar }
            .sheet(isPresented: $choosingEnd) { untilSheet }
            .sheet(isPresented: $savingPage) {
                ComposeSavePageSheet(name: String(session.input.text.components(separatedBy: "\n").first?.prefix(80) ?? ""),
                    descriptor: descriptor, store: store, save: savePage)
            }
            .sheet(item: $picker) { kind in
                ComposeInsertSheet(kind: kind, catalog: catalog, functions: functions, tools: tools,
                    validate: validateFormula) { source, wrapping in
                        edit(wrapping ? ComposeAuthoring.wrappingSelection(source, in: session.input)
                            : ComposeAuthoring.inserting(source, into: session.input))
                        picker = nil
                    }
            }
            .confirmationDialog("\(name) is silenced", isPresented: $silenceConfirmation, titleVisibility: .visible) {
                Button("Hold until silence ends") { chooseSilence(.hold); Task { await send() } }
                Button("Show anyway") { chooseSilence(.override); Task { await send() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Hold the message until silence ends, or explicitly show it during silence. The duration is \(durationLabel).")
            }
        }
        .tint(ShellPalette(appearance: appearance).tint)
        .figmaNode("compose:sheet", label: "Compose")
        .interactiveDismissDisabled(locked)
        .task(id: session.scope) { await loadCatalog() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await persist() } }
        }
    }

    @ViewBuilder private var connectionNotice: some View {
        if !live {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.networkAvailable ? "Can’t reach this display" : "You’re offline", systemImage: "wifi.slash")
                    .font(.headline)
                Text("Your message stays as a draft on this device. Reconnect and verify the display before showing it.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Retry") { Task { await verifyTarget(session.scope.target.boardID, session) } }
                    .disabled(locked).accessibilityIdentifier("composeReconnect")
            }.accessibilityIdentifier("composeOfflineNotice")
        } else if session.unavailableBufferedTargetID != nil {
            Text("The saved display is unavailable. Choose a display from Send to.").font(.callout)
        }
        if let error = session.previewFailure { Text(error).font(.callout).foregroundStyle(.secondary) }
    }
    private var displayMenu: some View {
        Menu {
            Section("Send to") {
                ForEach(store.boards) { board in
                    Button { Task { await verifyTarget(board.id, session) } } label: {
                        if board.id == session.scope.target.boardID { Label(board.name, systemImage: "checkmark") }
                        else { Text(board.name) }
                    }
                }
            }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 4) { Text(name).font(.subheadline.weight(.semibold)); Image(systemName: "chevron.up.chevron.down").font(.caption2) }
                Text(session.scope.target.deployment.description.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .disabled(locked || store.refreshing || store.needsReadback || store.pageLibrary?.needsReview == true)
        .accessibilityLabel("Display, \(name). Send to")
        .accessibilityIdentifier("composeDisplayPicker")
    }
    private var durationLabel: String {
        switch session.input.duration {
        case .minutes(let value): value == 60 ? "1 hr" : "\(value) min"
        case .until(let date): "Until \(date.formatted(date: .omitted, time: .shortened))"
        case .untilCancel: "Until I cancel"
        }
    }
    private var durationMenu: some View {
        Menu {
            Button("15 min") { chooseDuration(.minutes(15)) }
            Button("1 hr") { chooseDuration(.minutes(60)) }
            Button("Until a time…") { choosingEnd = true }
            Button("Until I cancel") { chooseDuration(.untilCancel) }
        } label: { Label(durationLabel, systemImage: "clock") }
            .buttonStyle(.bordered).disabled(locked).accessibilityIdentifier("composeDuration")
    }
    private var silenceMenu: some View {
        Menu {
            Button("Hold until silence ends") { chooseSilence(.hold) }
            Button("Show during silence") { chooseSilence(.override) }
        } label: { Label(session.input.silence == .hold ? "Respect silence" : "Show during silence", systemImage: "moon") }
            .buttonStyle(.bordered).disabled(locked).accessibilityIdentifier("composeSilence")
    }
    private var untilSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Show until", selection: $end, in: Date()...Date().addingTimeInterval(28_800), displayedComponents: [.date, .hourAndMinute])
                Text("Choose an end within the next 8 hours.").font(.footnote)
            }
            .navigationTitle("Duration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingEnd = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { chooseDuration(.until(end)); choosingEnd = false } }
            }
        }.presentationDetents([.medium])
    }
    private func edit(_ input: ComposeInput) {
        guard !locked else { return }
        session.update(input)
        Task { await persist() }
    }
    private func chooseDuration(_ duration: ComposeBufferDuration) {
        let old = session.input
        edit(.init(text: old.text, lineMetadata: old.lineMetadata, selection: old.selection, duration: duration, silence: old.silence))
    }
    private func chooseSilence(_ silence: ComposeBufferSilence) {
        let old = session.input
        edit(.init(text: old.text, lineMetadata: old.lineMetadata, selection: old.selection, duration: old.duration, silence: silence))
    }
    private func persist() async {
        do {
            if try await session.persistBuffer() == nil { notice = "Your latest draft could not be saved. Keep this sheet open and try again." }
        } catch { notice = "Your latest draft could not be saved. Keep this sheet open and try again." }
    }
    private func close() async {
        do {
            guard try await session.persistBuffer() != nil else { notice = "Your latest draft could not be saved. Try again before leaving."; return }
            session.close(); dismiss()
        } catch { notice = "Your latest draft could not be saved. Try again before leaving." }
    }
    private func request(input: ComposeInput, id: UUID = UUID(), preparedAt: Date = Date()) -> ComposeRequest? {
        guard live, let proof = store.composePrincipal, let detail = store.board,
              detail.summary.id == session.scope.target.boardID,
              proof.identity == session.scope.identity, proof.connectionID == session.scope.connectionID,
              let geometry = try? ComposeGeometry(summary: detail.summary) else { return nil }
        return .init(principal: proof, target: session.scope.target, requestID: id, preparedAt: preparedAt,
            text: input.text, lineMetadata: input.lineMetadata, geometry: geometry, duration: input.duration, silence: input.silence)
    }
    private func send() async {
        guard !locked, let captured = session.prepare() else { notice = "Check the display, message and duration before showing it."; return }
        preparing = true; defer { preparing = false }
        do {
            guard let revision = try await session.persistBuffer(),
                  let consumed = session.consume(captured),
                  let request = request(input: consumed.input, id: consumed.id, preparedAt: consumed.preparedAt),
                  let action = store.prepare(.compose(request)) else { notice = "The display or draft changed. Review it before showing it."; return }
            sentActionID = action.id; sentRevision = revision
            await store.confirm(action).value
            await clearAcknowledgedDraft()
        } catch { notice = "Your draft could not be saved. Nothing was sent." }
    }
    private func clearAcknowledgedDraft() async {
        guard let actionID = sentActionID, let revision = sentRevision,
              let operation = store.composeOperation, operation.actionID == actionID,
              operation.acceptedReadback, !store.needsReadback,
              [.sent, .unchanged].contains(operation.receipt.state) else { return }
        do {
            if try await session.clearBuffer(matchingRevision: revision) { dismiss() }
        } catch { notice = "The message was acknowledged, but the local draft could not be cleared." }
    }
    private func savePage(_ name: String) async -> Bool {
        guard !locked, store.canSaveComposePage, let request = request(input: session.input),
              let action = store.prepare(.composePage(name: name, request: request)) else { return false }
        preparing = true; defer { preparing = false }
        guard (try? await session.persistBuffer()) != nil else { notice = "Your draft could not be saved. Nothing was created."; return false }
        await store.confirm(action).value
        return store.composePageOperation?.actionID == action.id
    }
    @ViewBuilder private var outcome: some View {
        if let message = store.message { Text(message).font(.callout).accessibilityIdentifier("composeOutcome") }
        if store.commandBusy { ProgressView("Waiting for the hub…") }
        if store.canCheckComposeOutcome {
            Button("Check message outcome") {
                Task {
                    await store.checkComposeOutcome().value
                    await clearAcknowledgedDraft()
                }
            }.accessibilityIdentifier("composeCheckOutcome")
        } else if store.needsReadback, !store.commandBusy {
            Text("Waiting to check this message’s outcome. Reconnect or wait for the hub to become available.")
                .font(.callout).accessibilityIdentifier("composeOutcomeWaiting")
        }
        if store.pageLibrary?.needsReview == true {
            Button("Review Pages") { Task { await store.reviewPageLibrary() } }
            if case .reviewed? = store.pageLibrary?.phase {
                ForEach(store.pages) { page in Text(page.name).font(.callout) }
                Text("A matching page name does not confirm the earlier request.").font(.footnote)
                Button("I reviewed Pages") { store.acknowledgePageLibraryReview() }
            }
        }
    }
    private func loadCatalog() async {
        catalog = nil; functions = nil
        let capturedScope = session.scope
        guard let request = request(input: session.input) else { return }
        let loadedCatalog = try? await store.composeTemplateCatalog(request)
        guard !Task.isCancelled, session.scope == capturedScope else { return }
        catalog = loadedCatalog
        let loadedFunctions = try? await store.composeFormulaFunctions(request)
        guard !Task.isCancelled, session.scope == capturedScope else { return }
        functions = loadedFunctions
    }
    private func validateFormula(_ expression: String) async throws -> FormulaCheck {
        guard let request = request(input: session.input) else { throw FiestaBoardError.invalidTarget }
        return try await store.validateComposeFormula(expression, request: request)
    }
}

private extension ComposeEditor {
    var capabilityToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                tool("Variables", symbol: "curlybraces", kind: .variables, enabled: live && catalog?.hasVariables == true)
                if tools.textColor { tool("Text color", symbol: "paintpalette", kind: .textColor, enabled: catalog != nil) }
                else if tools.tiles { tool("Colors", symbol: "paintpalette", kind: .tiles, enabled: catalog != nil) }
                if !tools.icons.isEmpty { tool("Icon", symbol: "face.smiling", kind: .icons, enabled: true).accessibilityIdentifier("composeIcons") }
                Menu {
                    ForEach(["left", "center", "right"], id: \.self) { alignment in
                        Button(alignment.capitalized) { edit(ComposeAuthoring.formatting(session.input, alignment: alignment, wrap: selectedLine.wrap)) }
                    }
                    Button(selectedLine.wrap ? "Don’t wrap line" : "Wrap line") { edit(ComposeAuthoring.formatting(session.input, alignment: selectedLine.alignment, wrap: !selectedLine.wrap)) }
                    if live, catalog?.formatting.isEmpty == false { Button("Insert formatting…") { picker = .formatting } }
                } label: { Label("Formatting", systemImage: "textformat") }
                .disabled(locked)
                tool("Formula", symbol: "sum", kind: .formula, enabled: live && functions != nil)
                Menu {
                    Button("Save as Page") { savingPage = true }
                        .disabled(empty || !live || !store.canSaveComposePage)
                    if catalog == nil { Button("Retry tools") { Task { await loadCatalog() } }.disabled(!live) }
                    if tools.tiles && tools.textColor { Button("Color tiles") { picker = .tiles } }
                    if let font = drawing?.font { Text("Font: \(font) · Display setting") }
                } label: { Label("More", systemImage: "ellipsis") }
                .accessibilityIdentifier("composeMore")
            }
            .font(.caption).labelStyle(.titleAndIcon).padding(.horizontal, 18).padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12).padding(.bottom, 8)
        .figmaNode("compose:toolbar")
        .disabled(locked)
    }
    func tool(_ title: String, symbol: String, kind: ComposePicker, enabled: Bool) -> some View {
        Button { picker = kind } label: { Label(title, systemImage: symbol) }.disabled(!enabled || locked)
    }
}
