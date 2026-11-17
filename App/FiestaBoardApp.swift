import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

@main struct FiestaBoardApp: App {
    private let connectionPersistence = ConnectionPersistence(
        directory: AppPersistence.directory.appendingPathComponent("FiestaBoard/Servers", isDirectory: true))
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let kind = ParityFixtureView.Kind.fromLaunchArguments() {
                ParityFixtureView(kind: kind)
            } else {
                DraftScene(persistence: connectionPersistence)
            }
            #else
            DraftScene(persistence: connectionPersistence)
            #endif
        }
    }
}

/// UI tests use real services with isolated storage. Release ignores the test environment.
enum AppPersistence {
    static var directory: URL {
        let root = URL.applicationSupportDirectory
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["FIESTABOARD_TEST_NAMESPACE"], let id = UUID(uuidString: value) {
            return root.appendingPathComponent("UITests/" + id.uuidString, isDirectory: true)
        }
        #endif
        return root
    }
    static var preferences: UserDefaults {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["FIESTABOARD_TEST_NAMESPACE"], let id = UUID(uuidString: value) {
            return UserDefaults(suiteName: "FiestaBoard.UITests." + id.uuidString)!
        }
        #endif
        return .standard
    }
}

// Select the standard property-wrapper type explicitly; SDK 27 also overloads @State as a macro.
private typealias DraftState<Value> = SwiftUI.State<Value>

enum DraftTab: String, CaseIterable, Hashable, Identifiable {
    case home = "Home", displays = "Displays", pages = "Pages", collections = "Collections"
    case schedule = "Schedule", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .home: "house"
        case .displays: "rectangle.on.rectangle"
        case .pages: "doc.on.doc"
        case .collections: "rectangle.stack"
        case .schedule: "calendar"
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
            preferences: AppPersistence.preferences, serviceFactory: {
                let service = LiveFiestaBoardService(deployment: $0, vault: KeychainSessionVault(), clientMetadata: .init(deviceName: UIDevice.current.name))
                StatusReaderRegistry.shared.register(service)
                return service
            }))
    }
    @DraftState private var tab: DraftTab? = .home
    @DraftState private var compactColumn = NavigationSplitViewColumn.detail
    /// The sidebar hides while a page editor is open so the board gets the full width (B29).
    @DraftState private var columnVisibility = NavigationSplitViewVisibility.automatic
    @DraftState private var composing = false
    @DraftState private var textDraft = ""
    @DraftState private var started = false
    private let accent = Color.orange

    var body: some View {
        Group {
            if store.status == nil {
                ConnectionView(model: connection, store: store)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
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
                // EditorRoot reports EditorIsOpenKey while it is on screen (iOS-E2): full width
                // while editing, and the sidebar comes back when the editor closes.
                .onPreferenceChange(EditorIsOpenKey.self) { open in
                    withAnimation(.easeInOut(duration: 0.25)) { columnVisibility = open ? .detailOnly : .automatic }
                }
            }
        }
        .tint(accent)
        .onChange(of: store.selectedBoardID) { _, id in
            if let id, connection.phase == .connected, !connection.busy { Task { await connection.persistPreferredBoard(id) } }
        }
        .onChange(of: store.status == nil) { _, disconnected in
            if disconnected && !store.connecting { connection.storeConnectionChanged() }
        }
        .onChange(of: store.connecting) { _, connecting in
            if !connecting && store.status == nil { connection.storeConnectionChanged() }
            if !connecting && store.status != nil { boardStatus.start() } else if store.status == nil { boardStatus.stop() }
        }
        .sheet(isPresented: $composing) {
            NavigationStack {
                Form {
                    Section("Message") {
                        TextEditor(text: $textDraft).frame(minHeight: 150).accessibilityLabel("Message text")
                    }
                    Section {
                        Button("Send") {
                            if let action = store.prepare(.text(textDraft)) {
                                store.confirm(action); composing = false
                            }
                        }.disabled(!store.canWrite || textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Compose text")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { composing = false } } }
            }
        }
        .task {
            guard !started else { return }; started = true
            await connection.start().value
        }
    }

    @ViewBuilder private var destination: some View {
        switch tab ?? .home {
        case .home:
            NavigationStack {
                HomeView(store: store, status: boardStatus, compose: { composing = true },
                         preparePage: { if let action = store.prepare(.page($0)) { store.confirm(action) } },
                         prepareRestore: { if let action = store.prepare(.restore) { store.confirm(action) } },
                         openSettings: { tab = .settings }, openSchedule: { tab = .schedule },
                         changePage: { pageChooser }, controls: { boardControlsDestination() })
            }
        case .displays: displays
        case .pages: library
        case .collections: NavigationStack { CollectionsView(store: store) }
        case .schedule: NavigationStack { SchedulesView(store: store) }
        case .settings: settings
        }
    }

    private var connectionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.connectionLabel, systemImage: "network")
                .font(.subheadline.weight(.semibold)).textSelection(.enabled)
            Text("FiestaBoard hub")
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
                          prepare: { if let action = store.prepare(.page($0)) { store.confirm(action) } })
        }
    }
    private var pageChooser: some View {
        List(store.pages) { page in
            Button { if let action = store.prepare(.page(page.id)) { store.confirm(action) } } label: { Label(page.name, systemImage: "rectangle.stack") }
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
                    Button("Disconnect") { connection.disconnect() }
                    if store.status?.isDemo != true {
                        Button("Forget remembered sign-in") { Task { await connection.forgetSignIn() } }
                        if let warning = connection.persistence.warning {
                        Text(warning == .remoteRevocationPending ? "Remote sign-out is still pending. Sign out in the server web interface if needed." : "Remembered sign-in needs attention. Sign in again or forget the saved session.").font(.footnote).foregroundStyle(.orange)
                    }
                        Button("Log out & disconnect") { connection.logout() }
                    }
                }
                if !store.logoutNotices.isEmpty {
                    Section("Sign-out status") {
                        ForEach(store.logoutNotices) { notice in Text(notice.message).font(.footnote) }
                    }
                }
                Section("Notices") {
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
