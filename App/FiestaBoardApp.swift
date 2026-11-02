import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

@main struct FiestaBoardApp: App {
    private let connectionPersistence = ConnectionPersistence(
        directory: URL.applicationSupportDirectory.appendingPathComponent("FiestaBoard/Servers", isDirectory: true))
    var body: some Scene { WindowGroup { DraftScene(persistence: connectionPersistence) } }
}

// Select the standard property-wrapper type explicitly; SDK 27 also overloads @State as a macro.
private typealias DraftState<Value> = SwiftUI.State<Value>

enum DraftTab: String, CaseIterable, Hashable, Identifiable {
    case home = "Home", displays = "Displays", pages = "Pages", collections = "Collections"
    case schedule = "Schedule", integrations = "Integrations", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .home: "house"
        case .displays: "rectangle.on.rectangle"
        case .pages: "doc.on.doc"
        case .collections: "rectangle.stack"
        case .schedule: "calendar"
        case .integrations: "puzzlepiece.extension"
        case .settings: "gearshape"
        }
    }
}

struct DraftScene: View {
    @StateObject private var store: BoardStore
    @StateObject private var connection: ConnectionModel
    @StateObject private var boardStatus: BoardStatus
    @StateObject private var thumbnails: PageThumbnails
    init(persistence: ConnectionPersistence) {
        let store = BoardStore()
        _store = StateObject(wrappedValue: store)
        _thumbnails = StateObject(wrappedValue: PageThumbnails(reader: {
            StatusReaderRegistry.shared.previewReader(for: store.connectionLabel)
        }))
        _boardStatus = StateObject(wrappedValue: BoardStatus(store: store, reader: {
            StatusReaderRegistry.shared.reader(for: store.connectionLabel)
        }))
        _connection = StateObject(wrappedValue: ConnectionModel(
            store: store, catalog: persistence.catalog, discovery: BonjourServerDiscovery(),
            preferences: .standard, serviceFactory: {
                let service = LiveFiestaBoardService(deployment: $0, vault: KeychainSessionVault())
                StatusReaderRegistry.shared.register(service)
                return service
            }))
    }
    @DraftState private var tab: DraftTab? = .home
    @DraftState private var compactColumn = NavigationSplitViewColumn.detail
    @DraftState private var composing = false
    @DraftState private var textDraft = ""
    @DraftState private var reviewAfterCompose: PreparedAction?
    @DraftState private var pending: PreparedAction?
    @DraftState private var candidateWrites = false
    @DraftState private var started = false
    @DraftState private var demoMode = DemoSimulation.accepted
    private var demo: DemoFiestaBoardService? { connection.demoService }
    private let accent = Color.orange

    var body: some View {
        Group {
            if store.status == nil {
                ConnectionView(model: connection, store: store)
            } else {
                NavigationSplitView(preferredCompactColumn: $compactColumn) {
                    List(DraftTab.allCases, selection: $tab) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.rawValue, systemImage: destination.symbol)
                        }.accessibilityIdentifier("destination-" + destination.rawValue)
                    }
                    .navigationTitle("FiestaBoard")
                    .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
                } detail: {
                    destination
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .tint(accent)
        .onChange(of: store.selectedBoardID) { _, id in
            if let id, connection.phase == .connected, !connection.busy { Task { await connection.persistPreferredBoard(id) } }
        }
        .onChange(of: store.status == nil) { _, disconnected in
            if disconnected && !store.connecting { connection.storeConnectionChanged(); candidateWrites = false }
        }
        .onChange(of: store.connecting) { _, connecting in
            if !connecting && store.status == nil { connection.storeConnectionChanged(); candidateWrites = false }
            if !connecting && store.status != nil { boardStatus.start() } else if store.status == nil { boardStatus.stop() }
        }
        .sheet(isPresented: $composing, onDismiss: {
            if let action = reviewAfterCompose { reviewAfterCompose = nil; pending = action }
        }) {
            NavigationStack {
                Form {
                    Section("Message") {
                        TextEditor(text: $textDraft).frame(minHeight: 150).accessibilityLabel("Message text")
                    }
                    Section {
                        Text("Review captures this exact text and the selected board. Sending uses the server’s layout rules.")
                        Button("Review action") {
                            reviewAfterCompose = store.prepare(.text(textDraft))
                            if reviewAfterCompose != nil { composing = false }
                        }.disabled(!store.canWrite || textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle(store.status?.isDemo == true ? "Simulate a message" : "Compose text")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { composing = false } } }
            }
        }
        .sheet(item: $pending) { action in
            NavigationStack {
                Form {
                    Section("Captured destination") {
                        LabeledContent("Server", value: action.isDemo ? "Demo · simulated" : action.target.deployment.description)
                        LabeledContent("Board", value: action.boardName)
                        LabeledContent("Board ID", value: action.target.boardID)
                    }
                    Section("Captured action") {
                        switch action.payload {
                        case .text(let value): Text(value).font(.body.monospaced()).textSelection(.enabled)
                        case .page(let id): LabeledContent("Select page", value: pageName(id))
                        case .configuration(let patch):
                            if let paused = patch.paused { LabeledContent("Updates", value: paused ? "Pause" : "Resume") }
                            if let enabled = patch.scheduleEnabled { LabeledContent("Schedule", value: enabled ? "Follow schedule" : "Off") }
                            if let enabled = patch.autoRestore { LabeledContent("Automatic restore", value: enabled ? "On" : "Off") }
                            switch patch.defaultPage {
                            case .omit: EmptyView()
                            case .clear: Text("Clear the fallback page")
                            case .set(let id): LabeledContent("Fallback page", value: pageName(id))
                            }
                        case .restore:
                            Text("Restore the content FiestaBoard currently intends to show. The pinned selection remains in place; pause and silence settings still apply.")
                        }
                        Text(action.isDemo ? "This action stays in memory and does not contact hardware." : "The server may send this to the board. An acknowledgement does not verify physical output.").foregroundStyle(.secondary)
                    }
                    Section {
                        Button(action.isDemo ? "Confirm simulated action" : "Confirm board action") {
                            store.confirm(action); pending = nil
                        }.disabled(!store.canWrite)
                    }
                }
                .navigationTitle("Review action")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pending = nil } } }
            }
        }
        .task {
            guard !started else { return }; started = true
            await connection.start(demo: ProcessInfo.processInfo.arguments.contains("--demo")).value
        }
    }

    @ViewBuilder private var destination: some View {
        switch tab ?? .home {
        case .home:
            NavigationStack {
                HomeView(store: store, status: boardStatus, compose: { composing = true },
                         preparePage: { pending = store.prepare(.page($0)) },
                         openSettings: { tab = .settings }, openSchedule: { tab = .schedule },
                         changePage: { pageChooser }, controls: { boardControlsDestination() })
            }
        case .displays: displays
        case .pages: library
        case .collections: NavigationStack { CollectionsView(store: store) }
        case .schedule: NavigationStack { SchedulesView(store: store) }
        case .integrations:
            NavigationStack {
                ContentUnavailableView("Integrations", systemImage: "puzzlepiece.extension",
                    description: Text("Integration management is not available in this native draft. Use the server web interface to configure plugins and integrations."))
                    .navigationTitle("Integrations")
            }
        case .settings: settings
        }
    }

    private var connectionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.connectionLabel, systemImage: store.status?.isDemo == true ? "sparkles" : "network")
                .font(.subheadline.weight(.semibold)).textSelection(.enabled)
            Text(store.status?.isDemo == true ? "Demo · page saves, previews and board actions are simulated" : "FiestaBoard \(store.status?.version.displayedVersion ?? "(version unknown)") · \(store.status?.access == .candidateWrites ? "Changes from this app are on" : "Changes from this app are off")")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.message {
                Text(message).font(.callout).accessibilityIdentifier("actionOutcome")
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if store.commandBusy || store.refreshing { ProgressView(store.commandBusy ? "Waiting for server…" : "Refreshing…") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func boardControlsDestination(title: String = "Board controls") -> some View {
        Form {
            Section("Connection & action status") {
                connectionBanner
                if let reason = store.boardActionDisabledReason {
                    Text(reason.message).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Read current board state") {
                if store.needsReadback && !store.commandBusy {
                    Text("Refresh the board state before another action. Refresh reads current state and never repeats the previous action.")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("controlReadbackPrompt")
                }
                Button("Refresh board state") { store.refresh() }
                    .disabled(store.refreshing || store.commandBusy || store.connecting || store.status == nil || store.selectedBoardID == nil)
                    .accessibilityIdentifier("refreshBoardControls")
            }
            BoardControlsView(store: store)
        }
        .frame(maxWidth: 1000).frame(maxWidth: .infinity)
        .navigationTitle(title)
    }
    private func playback(for boardID: String) -> some View {
        Group {
            if store.selectedBoardID == boardID {
                boardControlsDestination(title: "Playback")
            } else {
                ProgressView("Selecting display…")
            }
        }
        .navigationTitle("Playback")
        .task { if store.selectedBoardID != boardID { await store.selectBoard(boardID).value } }
    }
    private var library: some View {
        NavigationStack {
            PagesListView(store: store, status: boardStatus, thumbnails: thumbnails,
                          prepare: { pending = store.prepare(.page($0)) })
        }
    }
    private var pageChooser: some View {
        List(store.pages) { page in
            Button { pending = store.prepare(.page(page.id)) } label: { Label(page.name, systemImage: "rectangle.stack") }
                .disabled(!store.canWrite)
        }.navigationTitle("Change page")
    }
    private var displays: some View {
        NavigationStack {
            DisplaysView(store: store, status: boardStatus, useOnHome: { tab = .home },
                         playback: { playback(for: $0) })
        }
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    connectionBanner
                    LabeledContent("Version", value: store.status?.version.displayedVersion ?? "Unknown")
                    LabeledContent("Board controls", value: store.status?.access.rawValue ?? "Disconnected")
                    Text("Passwords are never saved. Disconnect clears this window’s active session. Remembered sign-in stays securely stored until you forget it or log out.").font(.footnote).foregroundStyle(.secondary)
                    Button("Disconnect") { connection.disconnect(); candidateWrites = false }
                    if store.status?.isDemo != true {
                        Button("Forget remembered sign-in") { Task { await connection.forgetSignIn() } }
                        if let warning = connection.persistence.warning {
                        Text(warning == .remoteRevocationPending ? "Remote sign-out is still pending. Sign out in the server web interface if needed." : "Remembered sign-in needs attention. Sign in again or forget the saved session.").font(.footnote).foregroundStyle(.orange)
                    }
                        Button("Log out & disconnect") { connection.logout(); candidateWrites = false }
                    }
                }
                if !store.logoutNotices.isEmpty {
                    Section("Sign-out status") {
                        ForEach(store.logoutNotices) { notice in Text(notice.message).font(.footnote) }
                    }
                }
                if store.status?.isDemo == true {
                    Section("Simulate an outcome") {
                        Picker("Next action", selection: $demoMode) { ForEach(DemoSimulation.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            .accessibilityIdentifier("demoOutcomePicker")
                        Text("Demonstrate board outcomes without hardware. For page saves, Rejected simulates a revision conflict; Unknown and Partial simulate an uncertain save result.").font(.footnote)
                    }.onChange(of: demoMode) { _, value in if let demo { Task { await demo.setSimulation(value) } } }
                } else {
                    Section("Server changes") {
                        Toggle("Enable changes on this server", isOn: $candidateWrites)
                        DisclosureGroup("Compatibility details") { Text("Allow this app to change the selected display and save supported pages and collections. Applying this setting reconnects to the server. Board controls are tested with FiestaBoard 10.0.0, 10.1.17 and 10.1.20; other features check their own server support. Changes require confirmation. This is a test draft.").font(.footnote) }
                        Button("Apply change setting") { store.reconnect(allowCandidateWrites: candidateWrites) }.disabled(store.commandBusy || store.connecting)
                    }
                }
                Section("Server administration") {
                    Text("System settings and integration administration are not yet available here. Use the server web interface for those settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Local drafts") {
                    NavigationLink("Draft recovery & export") { LocalDraftRecoveryView() }
                        .accessibilityIdentifier("localDraftRecovery")
                }
                Section("About this draft") {
                    DraftScopeView()
                    NavigationLink("Open-source notices") {
                        ScrollView { Text(licenseText).font(.footnote.monospaced()).padding().textSelection(.enabled) }.navigationTitle("Notices")
                    }
                }
            }.frame(maxWidth: 1000).frame(maxWidth: .infinity).navigationTitle("Settings")
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "FiestaBoardTV-MIT", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "FiestaBoard TV mapping · MIT license. See ThirdPartyNotices in the source distribution." }
        return text
    }
    private func pageName(_ id: String?) -> String {
        guard let id else { return "None reported" }
        return store.pages.first(where: { $0.id == id })?.name ?? id
    }
}

private struct DraftScopeView: View {
    var body: some View {
        Text("Native draft: manual connection, page library, on-device drafts, supported page name and fixed template edits, explicit template validation and text preview, revision-checked server page saves, display selection, text and page actions, pause, schedule following, fallback page and restore controls. Refresh is manual; there is no background polling. Demo saves, evaluations and board actions are entirely simulated.")
        Text("Save local draft keeps a recovery copy on this device. A separate confirmed server save updates supported stored page fields when the server advertises the known page protocol and this session opts in. Native discovery, sign-in and initial server setup are available as a testable draft. Collections support revision-checked editing where available. Schedule lists and details are read-only. Flexible text and Canvas editing, OAuth, schedule editing, plugins and administration remain planned. Use the web interface for those features and full visual previews.")
        Text("No supported release pairing or full web/TV renderer parity is claimed.").font(.footnote).foregroundStyle(.secondary)
    }
}
