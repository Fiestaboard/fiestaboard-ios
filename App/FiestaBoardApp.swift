import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender
import FiestaBoardDocuments

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
    private let snapshots: ShellSnapshotStore
    private let composeBuffers: ComposeBufferStore
    @StateObject private var store: BoardStore
    @StateObject private var connection: ConnectionModel
    @StateObject private var boardStatus: BoardStatus
    @StateObject private var thumbnails: PageThumbnails
    @StateObject private var network = ShellNetwork()
    @DraftState private var shellConnection = ShellConnection()
    @DraftState private var retryBackoff = ShellBackoff()
    @DraftState private var connectingSince: TimeInterval?
    @DraftState private var cache = ShellCache<ShellSnapshot>()
    @DraftState private var now = Date().timeIntervalSince1970
    init(persistence: ConnectionPersistence) {
        snapshots = persistence.snapshots
        composeBuffers = ComposeBufferStore(directory: AppPersistence.directory.appendingPathComponent("FiestaBoard/Compose", isDirectory: true))
        let store = BoardStore()
        _store = StateObject(wrappedValue: store)
        _thumbnails = StateObject(wrappedValue: PageThumbnails(store: store, reader: {
            StatusReaderRegistry.shared.previewReader(for: store.connectionLabel)
        }))
        _boardStatus = StateObject(wrappedValue: BoardStatus(store: store, reader: {
            StatusReaderRegistry.shared.reader(for: store.connectionLabel)
        }))
        _connection = StateObject(wrappedValue: ConnectionModel(
            store: store, catalog: persistence.catalog, discovery: BonjourServerDiscovery(),
            preferences: AppPersistence.preferences, snapshots: persistence.snapshots, serviceFactory: {
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
            if phase == .checking { connectingSince = now; restoreCache() }
            else { connectingSince = nil }
            if case .authentication = phase { cache.remove(for: connection.address); shellConnection = .init() }
            if phase == .picker { shellConnection = .init(); cache.remove(for: connection.address) }
        }
        .onChange(of: connection.snapshotLease) { _, lease in
            if lease == nil { cache.remove(for: connection.address) } else { captureCache() }
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
            ComposeSheet(store: store, connection: connection, status: boardStatus, buffers: composeBuffers)
        }
        .task {
            guard !started else { return }; started = true
            store.networkAvailable = network.available
            await connection.start().value
            if let saved = connection.savedServers.first { await connection.selectSaved(saved).value }
        }
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
        guard store.status != nil, connection.phase == .connected, let hub = connection.selectedSavedHub,
              let lease = connection.snapshotLease, hub.deployment.description == store.connectionLabel else { return }
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(timeIntervalSince1970: now), board: store.board,
                                     displayName: store.boards.first { $0.id == store.selectedBoardID }?.name ?? "",
                                     pages: store.pages.map { .init(id: $0.id, name: $0.name) })
        cache.store(snapshot, for: store.connectionLabel, at: now)
        Task { _ = try? await snapshots.write(snapshot, lease: lease) }
    }
    private func restoreCache() {
        guard let hub = connection.selectedSavedHub else { return }
        let date = Date(timeIntervalSince1970: now)
        Task {
            guard let snapshot = try? await snapshots.read(for: hub, at: date),
                  connection.selectedSavedHub?.id == hub.id,
                  connection.phase == .checking || connection.phase == .unreachable else { return }
            cache.store(snapshot, for: hub.deployment.description, at: snapshot.capturedAt.timeIntervalSince1970)
        }
    }
    @ViewBuilder private func shellDestination(_ route: ShellTab) -> some View {
        if (connection.phase == .checking || connection.phase == .unreachable) && route == .more {
            more
        } else if connection.phase == .checking || connection.phase == .unreachable {
            NavigationStack {
                Group {
                if let cached = cache.value(for: shellHub, at: now), route == .pages {
                    ShellCachedContent(snapshot: cached, route: .pages, offline: presentation == .offline)
                } else if (connection.phase == .checking || presentation == .offline),
                          let cached = cache.value(for: shellHub, at: now), route == .home {
                    ShellCachedContent(snapshot: cached, route: .home, offline: presentation == .offline)
                } else {
                    ShellConnectionView(state: presentation, hub: activeHubName, retry: { connection.retrySavedHub() })
                        .navigationTitle(route.rawValue)
                }
                }
                .toolbar {
                    if route == .home, connection.composePrincipal != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button { composing = true } label: { Label("Compose", systemImage: "square.and.pencil") }
                                .accessibilityIdentifier("homeCompose")
                        }
                    }
                }
            }
        } else if presentation == .unreachable && route == .home {
            NavigationStack {
                ShellConnectionView(state: .unreachable, hub: activeHubName, retry: { store.probeReachability() })
                    .navigationTitle("Home")
                    .toolbar {
                        if connection.composePrincipal != nil {
                            ToolbarItem(placement: .primaryAction) {
                                Button { composing = true } label: { Label("Compose", systemImage: "square.and.pencil") }
                                    .accessibilityIdentifier("homeCompose")
                            }
                        }
                    }
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
                HomeView(store: store, status: boardStatus, thumbnails: thumbnails,
                         canCompose: connection.composePrincipal != nil, compose: { composing = true },
                         preparePage: { if let action = store.prepare(.page($0)) { store.confirm(action) } },
                         prepareRestore: { if let action = store.prepare(.restore) { store.confirm(action) } },
                         openSettings: { tab = .more }, openSchedule: { tab = .schedule },
                         controls: { boardControlsDestination() })
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
                            .accessibilityIdentifier("shellCollections")
                    }
                }
        }
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
    @ViewBuilder private var displayAccessory: some View {
        if store.selectedBoardID != nil {
            ShellDisplayAccessory(displays: store.boards, selectedID: store.selectedBoardID, nowShowing: boardStatus.nowShowing?.name,
                                  hubName: activeHubName, host: shellHub, disabled: store.connecting || store.commandBusy,
                                  select: { store.selectBoard($0) })
        } else if let cached = cache.value(for: shellHub, at: now), let board = cached.board {
            ShellDisplayAccessory(displays: [board.summary], selectedID: board.summary.id,
                                  nowShowing: cached.pages.first { $0.id == board.activePageID }?.name,
                                  hubName: activeHubName, host: shellHub, disabled: true, select: { _ in })
        }
    }
    private var more: some View {
        NavigationStack {
            ShellMoreRoot(hubName: activeHubName, host: shellHub, username: connection.snapshot?.auth.username,
                          savedCount: connection.savedServers.count, openDisplays: { tab = .displays },
                          account: { settings }, hubs: { hubs }) {
                ScrollView { Text(licenseText).font(.footnote.monospaced()).padding().textSelection(.enabled) }
                    .navigationTitle("About")
            }
        }
    }
    private var hubs: some View {
        ShellHubsView(hubs: connection.savedServers, activeDeployment: store.connectionLabel, busy: connection.busy,
                      select: { connection.selectSaved($0) }, add: {
            connection.disconnect(); connection.address = ""; connection.alias = ""; connection.username = ""
            connection.allowLocalHTTP = false; addingHub = true
        }, forget: { hub in Task { await connection.removeServer(hub) } }, notice: connection.message)
        .sheet(isPresented: $addingHub) { ConnectionView(model: connection, store: store) }
        .onChange(of: connection.phase) { _, phase in if phase == .connected { addingHub = false } }
    }
    private var settings: some View {
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
