import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

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

struct DraftScene: View {
    @StateObject private var store: BoardStore
    @StateObject private var connection: ConnectionModel
    @StateObject private var boardStatus: BoardStatus
    @StateObject private var thumbnails: PageThumbnails
    @StateObject private var network = ShellNetwork()
    @DraftState private var shellConnection = ShellConnection()
    @DraftState private var retryBackoff = ShellBackoff()
    @DraftState private var connectingSince: TimeInterval?
    @DraftState private var cache = ShellCache<CachedShell>()
    @DraftState private var now = Date().timeIntervalSince1970
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
    @DraftState private var tab: ShellTab = .home
    @DraftState private var editorOpen = false
    @DraftState private var addingHub = false
    /// The sidebar hides while a page editor is open so the board gets the full width (B29).
    @DraftState private var composing = false
    @DraftState private var textDraft = ""
    @DraftState private var started = false
    @Environment(\.colorScheme) private var appearance
    private var palette: ShellPalette { ShellPalette(appearance: appearance) }

    var body: some View {
        Group {
            if store.status == nil && connection.phase != .checking && connection.phase != .unreachable {
                ConnectionView(model: connection, store: store)
            } else {
                ShellContainer(selection: $tab, editorOpen: editorOpen, destination: shellDestination,
                               accessory: { displayAccessory })
                    .onPreferenceChange(EditorIsOpenKey.self) { editorOpen = $0 }
            }
        }
        .tint(palette.tint)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in now = date.timeIntervalSince1970 }
        .onChange(of: network.available) { _, available in
            store.networkAvailable = available
            observeConnection()
        }
        .onChange(of: store.hubReachable) { _, reachable in
            if reachable == true { retryBackoff.reset() }
            observeConnection()
        }
        .onChange(of: shellHub) { _, _ in retryBackoff.reset(); observeConnection() }
        .onChange(of: connection.phase) { _, phase in
            if phase == .checking { connectingSince = now }
            else { connectingSince = nil }
            if case .authentication = phase { cache.remove(for: connection.address); shellConnection = .init() }
            if phase == .picker { shellConnection = .init() }
        }
        .onChange(of: store.refreshing) { _, refreshing in
            if !refreshing && store.hubReachable == true { captureCache() }
        }
        .onChange(of: store.connecting) { _, connecting in
            if !connecting && store.hubReachable == true { captureCache() }
        }
        .task(id: presentation == .unreachable) {
            guard presentation == .unreachable else { return }
            while !Task.isCancelled && presentation == .unreachable {
                let delay = retryBackoff.next()
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, network.available else { return }
                if connection.phase == .unreachable { await connection.retrySavedHub().value }
                else { await store.probeReachability().value }
            }
        }
        .overlay(alignment: .top) {
            if shellConnection.reconnected {
                Text("Reconnected").padding().background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("shellReconnected")
                    .task { try? await Task.sleep(for: .seconds(3)); shellConnection.dismissReconnected() }
            }
        }
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
            store.networkAvailable = network.available
            await connection.start().value
            if let saved = connection.savedServers.first { await connection.selectSaved(saved).value }
        }
    }

    private struct CachedShell: Sendable {
        let board: BoardDetail?
        let display: String
        let pages: [Page]
    }
    private var shellHub: String { store.status == nil ? connection.address : store.connectionLabel }
    private var presentation: ShellConnection.Presentation {
        ShellConnection.presentation(pathAvailable: network.available, hubReachable: store.hubReachable == true,
                                     connectingSince: connectingSince, cachedAt: cache.timestamp(for: shellHub), now: now)
    }
    private func observeConnection() {
        shellConnection.observe(pathAvailable: network.available, hubReachable: store.hubReachable == true, hub: shellHub)
    }
    private func captureCache() {
        guard store.status != nil else { return }
        cache.store(CachedShell(board: store.board, display: store.boards.first { $0.id == store.selectedBoardID }?.name ?? "", pages: store.pages),
                    for: store.connectionLabel, at: now)
    }
    @ViewBuilder private func shellDestination(_ route: ShellTab) -> some View {
        if (connection.phase == .checking || connection.phase == .unreachable) && route == .more {
            more
        } else if connection.phase == .checking || connection.phase == .unreachable {
            NavigationStack {
                if let cached = cache.value(for: shellHub, at: now), route == .pages {
                    List(cached.pages) { page in Text(page.name) }.navigationTitle("Pages")
                        .safeAreaInset(edge: .top) { Text("Updating…").font(.callout).padding() }
                } else if connection.phase == .checking, let cached = cache.value(for: shellHub, at: now), route == .home {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Updating…").font(.callout)
                            Text(cached.display).font(.title)
                            if let detail = cached.board {
                                BoardViewport(frame: BoardFrame(detail), model: DisplayModel(summary: BoardSummaryFields(detail.summary), stored: nil))
                            }
                        }.padding().opacity(0.6)
                    }.navigationTitle("Home")
                } else {
                    ShellConnectionView(state: presentation, hub: activeHubName, retry: { connection.retrySavedHub() })
                        .navigationTitle(route.rawValue)
                }
            }
        } else if presentation == .unreachable && route == .home {
            NavigationStack {
                ShellConnectionView(state: .unreachable, hub: activeHubName, retry: { store.probeReachability() })
                    .navigationTitle("Home")
            }
        } else {
            destination(route)
                .safeAreaInset(edge: .top) {
                    if presentation == .offline { ShellConnectionView(state: .offline, hub: activeHubName, retry: {}) }
                }
        }
    }

    @ViewBuilder private func destination(_ route: ShellTab) -> some View {
        switch route {
        case .home:
            NavigationStack {
                HomeView(store: store, status: boardStatus, compose: { composing = true },
                         preparePage: { if let action = store.prepare(.page($0)) { store.confirm(action) } },
                         prepareRestore: { if let action = store.prepare(.restore) { store.confirm(action) } },
                         openSettings: { tab = .more }, openSchedule: { tab = .schedule },
                         changePage: { pageChooser }, controls: { boardControlsDestination() })
            }
        case .displays: displays
        case .pages: library
        case .schedule: NavigationStack { SchedulesView(store: store) }
        case .more: more
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { CollectionsView(store: store) } label: { Label("Collections", systemImage: "rectangle.stack") }
                    }
                }
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
    private var activeHubName: String {
        let saved = connection.selectedSavedHub ?? connection.savedServers.first { $0.deployment.description == store.connectionLabel }
        return saved?.alias.isEmpty == false ? saved!.alias : "FiestaBoard hub"
    }
    private var displayAccessory: some View {
        Menu {
            Section {
                Text(activeHubName)
                Text(store.connectionLabel)
            }
            ForEach(store.boards) { display in
                Button { store.selectBoard(display.id) } label: {
                    if display.id == store.selectedBoardID { Label(display.name, systemImage: "checkmark") }
                    else { Text(display.name) }
                }
                .disabled(store.connecting || store.commandBusy)
            }
        } label: {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                VStack(alignment: .leading) {
                    Text("Now showing · " + (boardStatus.nowShowing?.name ?? "No page selected"))
                        .font(.subheadline)
                    Text(store.boards.first { $0.id == store.selectedBoardID }?.name ?? "No display selected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }.padding(.horizontal)
        }
        .accessibilityIdentifier("shellDisplaySwitcher")
    }
    private var more: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeHubName).font(.headline)
                        Text(store.connectionLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                    NavigationLink { settings } label: {
                        Label(connection.snapshot?.auth.username ?? "Account", systemImage: "person.crop.circle")
                    }
                    Button {} label: { Label("FiestaBot", systemImage: "sparkles") }.disabled(true)
                }
                Section("Hub") {
                    Button {} label: { Label("Network", systemImage: "wifi") }.disabled(true)
                    Button {} label: { Label("AI provider", systemImage: "sparkles") }.disabled(true)
                    Button {} label: { Label("System & backups", systemImage: "externaldrive") }.disabled(true)
                    Button {} label: { Label("Language & time", systemImage: "clock") }.disabled(true)
                    NavigationLink { hubs } label: {
                        LabeledContent { Text("\(connection.savedServers.count) saved") } label: { Label("Hubs", systemImage: "externaldrive.connected.to.line.below") }
                    }.accessibilityIdentifier("shellHubs")
                }
                Section("Manage") {
                    NavigationLink { displays } label: { Label("Displays", systemImage: "rectangle.on.rectangle") }
                    Button {} label: { Label("Integrations", systemImage: "puzzlepiece.extension") }.disabled(true)
                }
                Section("Help") {
                    NavigationLink("About") {
                        ScrollView { Text(licenseText).font(.footnote.monospaced()).padding().textSelection(.enabled) }
                            .navigationTitle("About")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("More")
        }
    }
    private var hubs: some View {
        List {
            Section {
                ForEach(connection.savedServers) { hub in
                    Button { connection.selectSaved(hub) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(hub.alias.isEmpty ? hub.deployment.description : hub.alias)
                                Text(hub.deployment.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if hub.deployment.description == store.connectionLabel {
                                Label("Active", systemImage: "checkmark").font(.caption)
                            }
                        }
                    }
                    .disabled(connection.busy)
                }
                Button("Add a hub") { connection.disconnect(); connection.address = ""; addingHub = true }.accessibilityIdentifier("shellAddHub")
            } footer: {
                Text("Each hub keeps its own sign-in and selected display.")
            }
        }
        .navigationTitle("Hubs")
        .sheet(isPresented: $addingHub) { ConnectionView(model: connection, store: store) }
        .onChange(of: connection.phase) { _, phase in if phase == .connected { addingHub = false } }
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    connectionBanner
                    LabeledContent("Version", value: store.status?.version.displayedVersion ?? "Unknown")
                    LabeledContent("Board controls", value: store.status?.access.rawValue ?? "Disconnected")
                    Text("Passwords are never saved. Disconnect clears this window’s active session. Remembered sign-in stays securely stored until you forget it or log out.").font(.footnote).foregroundStyle(.secondary)
                    Button("Disconnect") { cache.remove(for: store.connectionLabel); connection.disconnect() }
                    if store.status?.isDemo != true {
                        Button("Forget remembered sign-in") { Task { await connection.forgetSignIn() } }
                        if let warning = connection.persistence.warning {
                        Text(warning == .remoteRevocationPending ? "Remote sign-out is still pending. Sign out in the server web interface if needed." : "Remembered sign-in needs attention. Sign in again or forget the saved session.").font(.footnote).foregroundStyle(.orange)
                    }
                        Button("Log out & disconnect") { cache.remove(for: store.connectionLabel); connection.logout() }
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
