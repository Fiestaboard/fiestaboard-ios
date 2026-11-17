import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

private typealias ConnectionState<Value> = SwiftUI.State<Value>

struct ConnectionView: View {
    @ObservedObject var model: ConnectionModel
    @ObservedObject var store: BoardStore
    /// I10 supplies its real scanner here; there is no inert or simulated pairing action.
    var scanPairingCode: (() -> Void)? = nil
    @ConnectionState private var removing: SavedServer?
    @ConnectionState private var renaming: SavedServer?
    @ConnectionState private var newAlias = ""
    @ConnectionState private var showWelcome = true
    @ConnectionState private var manualPresented = false
    private struct FormPresentation: Identifiable { let id: UUID }
    @ConnectionState private var formPresentation: FormPresentation?
    @ConnectionState private var presentedInitialForm = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var appearance
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    private var welcome: Bool { model.snapshot == nil && showWelcome }
    private var resetting: Bool {
        if let phase = model.passwordResetFlow?.phase { return phase != .passwordChanged }
        return false
    }
    private var title: String {
        if resetting { return "Reset password" }
        if model.snapshot != nil { return model.phase == .authentication(.signIn) ? "Sign in" : "Connect" }
        if welcome { return "Welcome" }
        return model.hubDiscoveryFlow.phase == .localNetworkExplanation ? "Local Network" : "Choose your hub"
    }
    var body: some View {
        Group {
            if sizeClass == .regular {
                ZStack {
                    palette.color("background").ignoresSafeArea()
                    OnboardingBackdrop(tiled: true).ignoresSafeArea()
                    if formPresentation == nil {
                        OnboardingAction(title: "Choose your hub") {
                            presentForm()
                        }.padding().frame(maxWidth: 360).accessibilityIdentifier("reopenOnboarding")
                    }
                }
                .sheet(item: formBinding) { presentation in
                    navigation(presentation).presentationSizing(.form).presentationDragIndicator(.visible)
                        .interactiveDismissDisabled(model.busy)
                }
            } else {
                navigation()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.returnFromWebSetup() } }
        .onChange(of: model.snapshot != nil) { _, verified in if verified { manualPresented = false } }
        .onAppear {
            if !presentedInitialForm {
                presentedInitialForm = true
                let intent = model.attachOnboardingPresentation()
                if sizeClass == .regular {
                    if model.snapshot == nil { showWelcome = false }
                    formPresentation = FormPresentation(id: intent)
                }
            }
        }
    }
    private func presentForm() {
        formPresentation = FormPresentation(id: model.beginOnboardingPresentation())
    }
    private func dismissForm(_ presentation: FormPresentation) {
        // A late binding callback must not hide a replacement form either.
        if formPresentation?.id == presentation.id { formPresentation = nil }
        model.dismissOnboardingPresentation(presentation.id)
    }
    private var formBinding: Binding<FormPresentation?> {
        // Capture the exact presented item before the system writes nil on a swipe.
        let presented = formPresentation
        return Binding(get: { formPresentation }, set: { next in
            if next == nil, let presented { dismissForm(presented) }
        })
    }
    private func navigation(_ presentation: FormPresentation? = nil) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = model.snapshot {
                        if model.setupWebReturn == .finished {
                            OnboardingNotice(title: "Setup finished on \(snapshot.deployment.description)", detail: "Your hub is ready. Connect this phone with a pairing code from Settings › Account › Connect a phone, or sign in.", symbol: "checkmark.circle", tone: "success")
                                .accessibilityIdentifier("webSetupFinished")
                            if let scanPairingCode {
                                OnboardingAction(title: "Scan a pairing code", action: scanPairingCode)
                            }
                        }
                        if model.passwordResetFlow?.phase == .passwordChanged {
                            OnboardingNotice(title: "Password changed", detail: "Every browser, TV and phone was signed out. Sign in with your new password.", symbol: "checkmark.circle", tone: "success")
                                .accessibilityIdentifier("passwordChanged")
                        }
                        if !resetting { OnboardingHubCard(name: hubName, address: snapshot.deployment.description) }
                        if case .authentication(let phase) = model.phase {
                            switch phase {
                            case .signIn:
                                if resetting { PasswordResetView(model: model) }
                                else { SignInView(model: model) }
                            case .chooseAuthentication, .setupAdministrator:
                                setup
                            case .ready: EmptyView()
                            }
                        }
                        if !resetting { connectionDetails(snapshot) }
                    } else if welcome {
                        welcomeContent
                    } else if model.hubDiscoveryFlow.phase == .localNetworkExplanation {
                        explanation
                    } else {
                        chooser
                    }
                    outcomes
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                palette.color("background")
                if welcome { OnboardingBackdrop().ignoresSafeArea() }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(welcome ? .large : .inline)
            .toolbar(welcome ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if resetting {
                        Button { model.cancelPasswordReset() } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Back to sign in").accessibilityIdentifier("cancelPasswordReset")
                    } else if let presentation {
                        Button { dismissForm(presentation) } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close onboarding")
                    } else if !welcome {
                        Button { model.cancel(); showWelcome = true } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Back to Welcome")
                    }
                }
            }
            .sheet(isPresented: $manualPresented) { manualAddress.presentationSizing(.form) }
            .confirmationDialog("Remove this hub and forget its saved sign-in?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove hub & forget sign-in", role: .destructive) {
                    if let hub = removing { Task { await model.removeServer(hub) } }; removing = nil
                }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                Text("Remove the saved address and forget this window’s remembered sign-in. Other windows keep active sessions; sign-ins saved after confirmation are protected.")
            }
            .alert("Rename hub", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Hub name", text: $newAlias)
                Button("Save") { if let hub = renaming { Task { await model.renameServer(hub, alias: newAlias) } }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
    private var hubName: String {
        let name = model.selectedSavedHub?.alias ?? model.snapshot?.identity.name ?? ""
        return name.isEmpty ? "FiestaBoard" : name
    }
    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Color.clear.frame(height: 220).accessibilityHidden(true)
            Image("OnboardingBrand").frame(width: 64, height: 64).accessibilityHidden(true)
            Text("Welcome to FiestaBoard").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text("Let’s get you set up in just a few steps. First, we’ll find the FiestaBoard hub on your home network.")
                .foregroundStyle(.secondary)
            OnboardingPrivacyNote()
            OnboardingAction(title: "Find my hub", leadingImage: "OnboardingFind") { showWelcome = false; model.attachOnboardingPresentation(); model.findServers() }
                .accessibilityIdentifier("findFiestaBoard")
            OnboardingAction(title: "Enter address", primary: false, action: enterAddress)
                .accessibilityIdentifier("enterHubAddress")
            if let scanPairingCode { OnboardingAction(title: "Scan QR code from the web app", primary: false, leadingImage: "OnboardingQR", action: scanPairingCode) }
            if !model.savedServers.isEmpty {
                Button("Choose a saved hub") { showWelcome = false }.frame(minHeight: 44)
            }
        }
    }
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find your hub on this Wi-Fi").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text("Your FiestaBoard hub lives on your home network, not in a cloud. To find it, your device will ask whether FiestaBoard may find devices on your local network. Choose Allow.")
                .foregroundStyle(.secondary)
            Text("WHAT FIESTABOARD LOOKS FOR").font(.caption).foregroundStyle(.secondary)
            OnboardingHubCard(name: "FiestaBoard hubs", address: "Like fiestapi.local, on port 4420")
            OnboardingHubCard(name: "Displays you add", address: "Split-flap displays, pixel displays and TVs, only when you ask")
            Text("This permission is only used to find FiestaBoard hubs and displays on this Wi-Fi. Change it any time in Settings › Privacy & Security › Local Network.")
                .font(.subheadline).foregroundStyle(.secondary)
            OnboardingAction(title: "Continue") { model.continueDiscoveryAfterExplanation() }
                .accessibilityIdentifier("discoveryContinue")
            OnboardingAction(title: "Enter an address instead", primary: false, action: enterAddress)
                .accessibilityIdentifier("enterAddressInstead")
        }
    }
    private var chooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your hub").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if !model.savedServers.isEmpty {
                Text("SAVED HUBS").font(.caption).foregroundStyle(.secondary)
                ForEach(model.savedServers) { hub in
                    VStack(alignment: .leading, spacing: 4) {
                        Button { model.attachOnboardingPresentation(); model.selectSaved(hub) } label: {
                            OnboardingHubCard(name: hub.alias.isEmpty ? "FiestaBoard" : hub.alias, address: hub.deployment.description)
                        }.buttonStyle(.plain)
                        HStack {
                            Button("Rename") { newAlias = hub.alias; renaming = hub }
                            Button("Remove", role: .destructive) { removing = hub }
                        }.buttonStyle(.borderless).frame(minHeight: 44)
                    }
                }
            }
            ForEach(model.discoveredServers) { hub in
                Button { model.useDiscovered(hub); enterAddress() } label: {
                    OnboardingHubCard(name: hub.displayName, address: hub.deployment.description)
                }.buttonStyle(.plain)
            }
            if model.searching {
                HStack {
                    Image("OnboardingSearch").renderingMode(.template).accessibilityHidden(true)
                    ProgressView("Looking for FiestaBoard hubs…")
                }
                Button("Stop searching") { model.stopDiscovery() }.frame(minHeight: 44)
            } else {
                if let message = model.discoveryMessage { Text(message).foregroundStyle(.secondary) }
                Button("Find hubs") { model.findServers() }.frame(minHeight: 44).accessibilityIdentifier("findFiestaBoard")
            }
            OnboardingAction(title: "Enter address", primary: false, leadingImage: "OnboardingAddress", action: enterAddress)
                .accessibilityIdentifier("enterHubAddress")
            if let scanPairingCode { OnboardingAction(title: "Scan QR code", primary: false, leadingImage: "OnboardingQR", action: scanPairingCode) }
            Text("Only FiestaBoard hubs are listed. Docker installs don’t announce themselves unless host networking and mDNS are set up, so enter their address.")
                .font(.subheadline).foregroundStyle(.secondary)
            OnboardingPrivacyNote()
        }.disabled(model.busy)
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingNotice(title: model.setupWebReturn == .incomplete ? "Setup isn't finished yet" : "This hub isn't set up yet", detail: "Finish setup in your hub’s web app. Keep this address; when you return, we’ll check whether your hub is ready.")
            if model.setupWebReturn == .unconfirmed {
                Text("We couldn't confirm the hub’s current state. Check the connection, then check again.")
            }
            OnboardingAction(title: "Open hub setup in browser") {
                if let url = model.beginWebSetup() { openURL(url) }
            }.disabled(model.busy || model.requiresStateCheck).accessibilityIdentifier("openWebSetup")
            if model.setupWebReturn == .awaitingReturn || model.setupWebReturn == .checking {
                Button("I'm back — check setup") { model.returnFromWebSetup() }.disabled(model.busy)
                    .frame(minHeight: 44).accessibilityIdentifier("checkWebSetup")
            }
        }
    }
    @ViewBuilder private var outcomes: some View {
        if model.busy && model.passwordResetFlow == nil { ProgressView("Checking hub…") }
        if let message = model.message ?? store.message, !model.signInPasswordRejected,
           model.passwordResetFlow?.invalidFields.isEmpty != false {
            Text(message).font(.callout).foregroundStyle(palette.color("destructive")).accessibilityIdentifier("connectionMessage")
        }
        if model.requiresStateCheck {
            Text("Check the hub’s current state before starting a new attempt. The previous request will not be repeated.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if model.snapshot != nil && !resetting {
            Button("Check hub state") { model.checkServerState() }.disabled(model.busy).frame(minHeight: 44)
        }
        ForEach(store.logoutNotices) { notice in Text(notice.message).font(.callout) }
    }
    private func connectionDetails(_ snapshot: BootstrapSnapshot) -> some View {
        DisclosureGroup("Hub details") {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.deployment.description).textSelection(.enabled)
                Text(snapshot.deployment.description.hasPrefix("https:") ? "HTTPS" : "Local HTTP · unencrypted")
                Text("Installation: " + snapshot.identity.installationID).textSelection(.enabled)
                Text("Version: " + snapshot.identity.version)
            }.font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var manualAddress: some View {
        NavigationStack {
            ManualHubAddressView(model: model)
                .navigationTitle("Enter address").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { manualPresented = false } label: { Image(systemName: "xmark") }.accessibilityLabel("Close address entry")
                    }
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func enterAddress() {
        model.attachOnboardingPresentation()
        showWelcome = false; model.enterManualAddress(); manualPresented = true
    }
}

private struct ManualHubAddressView: View {
    @ObservedObject var model: ConnectionModel
    @FocusState private var addressFocused: Bool
    @Environment(\.colorScheme) private var appearance
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hub address").font(.subheadline.weight(.medium))
                    TextField("Hub address", text: $model.address)
                        .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($addressFocused).submitLabel(.go).onSubmit { connect() }
                        .accessibilityIdentifier("connectionAddress")
                    Text("The address you open FiestaBoard at in a browser. Include https:// for a remote address or a reverse proxy prefix.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Allow HTTP on my local network", isOn: $model.allowLocalHTTP).accessibilityIdentifier("connectionLocalHTTP")
                Text("HTTP does not encrypt your connection. Enable it only for a trusted local hub.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                OnboardingAction(title: "Connect", action: connect).disabled(model.address.isEmpty || model.busy)
                    .accessibilityIdentifier("connectionConnect")
                if let message = model.message { Text(message).accessibilityIdentifier("connectionMessage") }
            }
            Section {
                TextField("Hub name (optional)", text: $model.alias)
                DisclosureGroup("Home Assistant or reverse proxy?") {
                    Text("Use a direct FiestaBoard endpoint or a proxy prefix that accepts this app's sign-in. A browser-only Home Assistant ingress URL needs its own upstream authentication; the app cannot reuse Safari cookies.").font(.footnote)
                }
            }
        }.disabled(model.busy).scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden).background(OnboardingPalette(appearance: appearance).color("background"))
    }
    private func connect() { addressFocused = false; model.connectAddress() }
}
