import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

private typealias ConnectionState<Value> = SwiftUI.State<Value>

struct ConnectionView: View {
    @ObservedObject var model: ConnectionModel
    @ObservedObject var store: BoardStore
    @ConnectionState private var removing: SavedServer?
    @ConnectionState private var renaming: SavedServer?
    @ConnectionState private var newAlias = ""
    @FocusState private var focusedField: Field?
    private enum Field { case address, alias }
    var body: some View {
        NavigationStack {
            Form {
                if model.snapshot == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "rectangle.split.3x3.fill").font(.largeTitle).foregroundStyle(.orange).accessibilityHidden(true)
                            Text("Connect your FiestaBoard").font(.title.bold())
                            Text("Connect to your FiestaBoard hub.").foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    if !model.savedServers.isEmpty {
                        Section("Saved servers") {
                            ForEach(model.savedServers) { server in
                                VStack(alignment: .leading, spacing: 8) {
                                    Button { focusedField = nil; model.selectSaved(server) } label: {
                                        VStack(alignment: .leading) {
                                            Text(server.alias.isEmpty ? "FiestaBoard" : server.alias).font(.headline)
                                            Text(server.deployment.description).font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    HStack {
                                        Button("Rename") { newAlias = server.alias; renaming = server }
                                        Button("Remove", role: .destructive) { removing = server }
                                    }.font(.caption).buttonStyle(.borderless)
                                }
                            }
                        }.disabled(model.busy)
                    }
                    Section("Find FiestaBoard") {
                        Button("Find FiestaBoard") { focusedField = nil; model.findServers() }
                            .accessibilityIdentifier("findFiestaBoard").disabled(model.searching || model.busy)
                        if model.searching {
                            ProgressView("Searching local network…")
                            Button("Stop searching") { model.stopDiscovery() }
                        }
                        ForEach(model.discoveredServers) { server in
                            Button { model.useDiscovered(server) } label: {
                                VStack(alignment: .leading) {
                                    Text(server.displayName)
                                    Text(server.deployment.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let message = model.discoveryMessage { Text(message).font(.callout) }
                        Text("Discovery uses your local network. You can always enter an address below.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Manual server connection") {
                        TextField("Server address", text: $model.address)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focusedField, equals: .address).submitLabel(.go).onSubmit { connect() }
                            .accessibilityIdentifier("connectionAddress")
                        TextField("Server name (optional)", text: $model.alias)
                            .focused($focusedField, equals: .alias)
                        Toggle("Allow HTTP on my local network", isOn: $model.allowLocalHTTP)
                            .accessibilityIdentifier("connectionLocalHTTP")
                        Text("Use the address you open in your browser. For a local HTTP address, enable the switch above. HTTP does not encrypt your connection.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Connect", action: connect).disabled(model.address.isEmpty || model.busy)
                            .accessibilityIdentifier("connectionConnect")
                        DisclosureGroup("Home Assistant or reverse proxy?") {
                            Text("Use a direct FiestaBoard endpoint or a proxy prefix that accepts this app's sign-in. A browser-only Home Assistant ingress URL needs its own upstream authentication; the app cannot reuse Safari cookies.")
                                .font(.footnote)
                        }
                    }.disabled(model.busy)
                }
                if let snapshot = model.snapshot {
                    Section("Server") {
                        LabeledContent("Name", value: snapshot.identity.name.isEmpty ? "FiestaBoard" : snapshot.identity.name)
                        LabeledContent("Address", value: snapshot.deployment.description).textSelection(.enabled)
                        LabeledContent("Transport", value: snapshot.deployment.description.hasPrefix("https:") ? "HTTPS" : "Local HTTP · unencrypted")
                        DisclosureGroup("Identity & compatibility") {
                            LabeledContent("Installation", value: snapshot.identity.installationID).textSelection(.enabled)
                            LabeledContent("Version", value: snapshot.identity.version)
                            Text("Each feature checks its own hub support. Sign in to control your displays.")
                        }
                        if !snapshot.health.serviceRunning { Text("The server is reachable. Its display service is not currently running.").foregroundStyle(.secondary) }
                    }
                    if case .authentication(let phase) = model.phase {
                        switch phase {
                        case .signIn: SignInView(model: model)
                        case .chooseAuthentication, .setupAdministrator:
                            if let url = URL(string: snapshot.deployment.description) {
                                Link("Finish setup in your browser", destination: url)
                            }
                        case .ready: EmptyView()
                        }
                    }
                }
                if !store.logoutNotices.isEmpty {
                    Section("Sign-out status") {
                        ForEach(store.logoutNotices) { notice in Text(notice.message).font(.callout) }
                    }
                }
                if model.busy || model.message != nil || store.message != nil || model.snapshot != nil {
                    Section {
                        if model.busy { ProgressView("Checking server…") }
                        if let message = model.message ?? store.message {
                            Text(message).foregroundStyle(.orange).accessibilityIdentifier("connectionMessage")
                        }
                        if model.requiresStateCheck {
                            Text("Check the server's current state before starting a new attempt. The previous request will not be repeated.").font(.footnote)
                        }
                        if model.snapshot != nil {
                            Button("Check server state") { model.checkServerState() }.disabled(model.busy)
                        }
                        Button(model.busy ? "Cancel" : "Choose another server") { model.cancel() }
                    }
                }
            }
            .navigationTitle("Welcome")
            .confirmationDialog("Remove this server and forget its saved sign-in?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove server & forget sign-in", role: .destructive) {
                    if let server = removing { Task { await model.removeServer(server) } }; removing = nil
                }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                Text("Remove the saved address and forget this window’s remembered sign-in. For a server not opened here, confirmation targets the sign-in currently stored. Other windows keep active sessions; sign-ins saved after confirmation are protected.")
            }
            .alert("Rename server", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Server name", text: $newAlias)
                Button("Save") { if let server = renaming { Task { await model.renameServer(server, alias: newAlias) } }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
    private func connect() { focusedField = nil; model.connectAddress() }
}
