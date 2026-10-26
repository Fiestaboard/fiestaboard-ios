import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

@main struct FiestaBoardApp: App {
    var body: some Scene { WindowGroup { DraftScene() } }
}

// Select the standard property-wrapper type explicitly; SDK 27 also overloads @State as a macro.
private typealias DraftState<Value> = SwiftUI.State<Value>

enum DraftTab: Hashable { case home, library, displays, settings }

struct DraftScene: View {
    @StateObject private var store = BoardStore()
    @DraftState private var tab = DraftTab.home
    @DraftState private var search = ""
    @DraftState private var composing = false
    @DraftState private var textDraft = ""
    @DraftState private var reviewAfterCompose: PreparedAction?
    @DraftState private var pending: PreparedAction?
    @DraftState private var candidateWrites = false
    @DraftState private var started = false
    @DraftState private var demoMode = DemoSimulation.accepted
    @DraftState private var demo: DemoFiestaBoardService?
    private let accent = Color.orange

    var body: some View {
        Group {
            if store.status == nil {
                WelcomeView(store: store, startDemo: startDemo)
            } else {
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "house", value: .home) { home }
                    Tab("Library", systemImage: "square.grid.2x2", value: .library) { library }
                    Tab("Displays", systemImage: "rectangle.on.rectangle", value: .displays) { displays }
                    Tab("Settings", systemImage: "gearshape", value: .settings) { settings }
                }
                .tabViewStyle(.sidebarAdaptable)
            }
        }
        .tint(accent)
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
            if ProcessInfo.processInfo.arguments.contains("--demo") { startDemo() }
        }
    }

    private var connectionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.connectionLabel, systemImage: store.status?.isDemo == true ? "sparkles" : "network")
                .font(.subheadline.weight(.semibold)).textSelection(.enabled)
            Text(store.status?.isDemo == true ? "Demo · board actions are simulated" : "\(store.status?.version.displayedVersion ?? "Unknown version") · \(store.status?.access == .candidateWrites ? "Draft controls enabled" : "Read-only")")
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
    private var home: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        connectionBanner
                        let wide = geometry.size.width > 760
                        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
                        layout {
                            VStack(alignment: .leading, spacing: 16) {
                                boardPicker
                                if let board = store.board {
                                    Text("Server-reported output").font(.headline)
                                    BoardOutputView(board: board)
                                    Text("Reported content may be cached. This is not independent physical readback.").font(.caption).foregroundStyle(.secondary)
                                    if let date = board.readAt { Text("Server read: \(date)").font(.caption).foregroundStyle(.secondary) }
                                    if board.expectedCharacters != nil && board.expectedCharacters != board.characters {
                                        DisclosureGroup("Expected output differs") { BoardOutputView(board: board, expected: true) }
                                    }
                                } else if store.boards.isEmpty {
                                    ContentUnavailableView("No displays", systemImage: "rectangle.on.rectangle", description: Text("This deployment has no boards to select."))
                                }
                            }.frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Make room for a little joy.", systemImage: "sun.max").font(.title2.bold())
                                Button { composing = true } label: { Label("Compose text", systemImage: "square.and.pencil").frame(maxWidth: .infinity, minHeight: 36) }
                                    .buttonStyle(.borderedProminent).disabled(!store.canWrite)
                                if store.status?.access == .readOnly { Text("This connection is read-only. See Settings for the draft’s exact version gate.").font(.callout).foregroundStyle(.secondary) }
                                if store.needsReadback { Text("Refresh output before another action.").font(.callout).foregroundStyle(.orange) }
                                if let board = store.board {
                                    selectionDetails(board)
                                    NavigationLink { pageChooser } label: { Label("Choose a page", systemImage: "rectangle.stack") }
                                        .buttonStyle(.bordered).disabled(!store.canWrite)
                                    NavigationLink {
                                        Form { BoardControlsView(store: store) }
                                            .navigationTitle("Board controls")
                                    } label: { Label("Board controls", systemImage: "slider.horizontal.3") }
                                        .buttonStyle(.bordered)
                                        .accessibilityIdentifier("boardControlsEntry")
                                }
                            }.frame(maxWidth: wide ? 290 : .infinity, alignment: .leading)
                        }
                    }.padding().frame(maxWidth: 1250).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("FiestaBoard")
            .toolbar { ToolbarItem(placement: .primaryAction) { refreshButton } }
        }
    }
    private var boardPicker: some View {
        Picker("Display", selection: Binding(get: { store.selectedBoardID ?? "" }, set: { store.selectBoard($0) })) {
            ForEach(store.boards) { Text($0.name).tag($0.id) }
        }.pickerStyle(.menu).disabled(store.commandBusy || store.refreshing)
    }
    private var refreshButton: some View {
        Button { store.refresh() } label: { Label("Refresh output", systemImage: "arrow.clockwise") }
            .disabled(store.refreshing || store.commandBusy)
    }
    private func selectionDetails(_ board: BoardDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selection & delivery").font(.headline)
            LabeledContent("Selected page", value: pageName(board.activePageID))
            LabeledContent("Resolved page", value: pageName(board.resolvedPageID))
            LabeledContent("Scheduled page", value: pageName(board.scheduledPageID))
            LabeledContent("Source", value: board.source)
        }.font(.subheadline)
    }
    private var library: some View {
        NavigationStack {
            List {
                Section { connectionBanner }
                Section("Pages · local drafts available") {
                    ForEach(store.pages.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { page in
                        NavigationLink { PageDetailView(page: page, store: store, prepare: { pending = store.prepare(.page(page.id)) }) } label: {
                            Label { VStack(alignment: .leading, spacing: 4) { Text(page.name).font(.headline); Text("\(page.type) · \(page.deviceType)").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "rectangle.stack").foregroundStyle(.orange) }.padding(.vertical, 6)
                        }
                    }
                    if store.pages.isEmpty { Text("No pages on this deployment.") }
                }
            }.navigationTitle("Library").searchable(text: $search, prompt: "Find a page")
        }
    }
    private var pageChooser: some View {
        List(store.pages) { page in
            Button { pending = store.prepare(.page(page.id)) } label: { Label(page.name, systemImage: "rectangle.stack") }
                .disabled(!store.canWrite)
        }.navigationTitle("Show on selected board")
    }
    private var displays: some View {
        NavigationStack {
            List {
                Section { connectionBanner }
                Section("Displays") {
                    ForEach(store.boards) { board in
                        NavigationLink {
                            Form {
                                Section("Display") {
                                    LabeledContent("Name", value: board.name)
                                    LabeledContent("ID", value: board.id)
                                    LabeledContent("Geometry", value: "\(board.rows) × \(board.cols)")
                                    LabeledContent("Device model", value: board.deviceModel ?? "Not reported")
                                    LabeledContent("Character set", value: board.charset ?? "Not reported")
                                    LabeledContent("Schedule", value: board.scheduleEnabled ? "Enabled" : "Disabled")
                                    LabeledContent("Paused", value: board.paused ? "Yes" : "No")
                                }
                                Section { Button("Use this display") { store.selectBoard(board.id); tab = .home }.disabled(store.commandBusy) }
                            }.navigationTitle(board.name)
                        } label: {
                            HStack { Label(board.name, systemImage: "rectangle.on.rectangle"); Spacer(); if store.selectedBoardID == board.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("Selected") } }
                        }
                    }
                    if store.boards.isEmpty { Text("No displays reported by this server.") }
                }
            }.navigationTitle("Displays")
        }
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    connectionBanner
                    LabeledContent("Version", value: store.status?.version.displayedVersion ?? "Unknown")
                    LabeledContent("Access", value: store.status?.access.rawValue ?? "Disconnected")
                    Text("Sessions stay in memory for this window. Passwords are never saved. Closing the app or disconnecting clears the local session.").font(.footnote).foregroundStyle(.secondary)
                    Button("Disconnect") { store.disconnect(); demo = nil; candidateWrites = false }
                    if store.status?.isDemo != true { Button("Log out & disconnect") { store.logout(); candidateWrites = false } }
                }
                if store.status?.isDemo == true {
                    Section("Simulate an outcome") {
                        Picker("Next action", selection: $demoMode) { ForEach(DemoSimulation.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        Text("Demonstrate held, partial, rejected and unknown results without hardware.").font(.footnote)
                    }.onChange(of: demoMode) { _, value in if let demo { Task { await demo.setSimulation(value) } } }
                } else {
                    Section("Draft controls") {
                        Toggle("Enable controls on this server", isOn: $candidateWrites)
                        Text("Controls use the FiestaBoard 10.0.0 test schema and can change the chosen board. Only that exact server version can enable them here; other versions stay read-only. This draft has no supported release pairing.").font(.footnote)
                        Button("Apply control setting") { store.reconnect(allowCandidateWrites: candidateWrites) }.disabled(store.commandBusy || store.connecting)
                    }
                }
                Section("About this draft") {
                    DraftScopeView()
                    NavigationLink("Open-source notices") {
                        ScrollView { Text(licenseText).font(.footnote.monospaced()).padding().textSelection(.enabled) }.navigationTitle("Notices")
                    }
                }
            }.navigationTitle("Settings")
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "FiestaBoardTV-MIT", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "FiestaBoard TV mapping · MIT license. See ThirdPartyNotices in the source distribution." }
        return text
    }
    private func startDemo() {
        do { let next = try DemoFiestaBoardService(); demo = next; demoMode = .accepted; store.connect(next) }
        catch { store.disconnect() }
    }
    private func pageName(_ id: String?) -> String {
        guard let id else { return "None reported" }
        return store.pages.first(where: { $0.id == id })?.name ?? id
    }
}

private struct WelcomeView: View {
    @ObservedObject var store: BoardStore
    let startDemo: () -> Void
    @DraftState private var serverURL = ""
    @DraftState private var localHTTP = false
    @DraftState private var username = ""
    @DraftState private var password = ""
    @DraftState private var validationError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "rectangle.split.3x3.fill").font(.system(size: 56)).foregroundStyle(.orange).accessibilityHidden(true)
                        Text("A little more\nFiesta, everywhere.").font(.largeTitle.bold())
                        Text("Keep an eye on your displays and put a thought on the board.").foregroundStyle(.secondary)
                        Button("Explore Demo", action: startDemo).buttonStyle(.borderedProminent).controlSize(.large).disabled(store.connecting)
                    }.padding(.vertical)
                }
                Section("Manual server connection") {
                    TextField("https://board.example.com/prefix", text: $serverURL).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Server URL")
                    Toggle("Allow HTTP on my local network", isOn: $localHTTP)
                    Text("Enter the deployment URL, including any proxy prefix. The app adds /api. HTTPS is required for public servers.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sign in if required") {
                    TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    Text("Credentials are used only for this connection attempt. Passwords are cleared from this form immediately.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Connect read-only") {
                        let secret = password; password = ""; validationError = nil
                        do {
                            let deployment = try DeploymentURL(serverURL, allowLocalHTTP: localHTTP)
                            store.connect(LiveFiestaBoardService(deployment: deployment), username: username, password: secret)
                        } catch { validationError = (error as? FiestaBoardError)?.localizedDescription ?? "Check the server URL." }
                    }.disabled(store.connecting || serverURL.isEmpty)
                    if store.connecting { ProgressView("Connecting…"); Button("Cancel") { store.disconnect() } }
                    if let error = validationError { Text(error).foregroundStyle(.red) }
                    else if let message = store.message {
                        Label(message, systemImage: store.remoteLogoutState == .succeeded ? "checkmark.circle" : store.remoteLogoutState == .pending ? "clock" : "exclamationmark.triangle")
                            .foregroundStyle(store.remoteLogoutState == .succeeded || store.remoteLogoutState == .pending ? Color.secondary : Color.red)
                    }
                }
                Section("Draft details") { DraftScopeView() }
            }.navigationTitle("Welcome")
        }
    }
}
private struct DraftScopeView: View {
    var body: some View {
        Text("Native draft: manual connection, page library, on-device page drafts, display selection, text and page actions, pause, schedule following, fallback page and restore controls. Refresh is manual; there is no background polling. Demo board actions are entirely simulated.")
        Text("Local drafts stay on this device and are never published to the server. Discovery, server setup, OAuth, publishing pages, schedule editing, plugins, administration and pixel rendering are still planned. Use the server’s web interface for those features.")
        Text("No supported release pairing or full web/TV renderer parity is claimed.").font(.footnote).foregroundStyle(.secondary)
    }
}
