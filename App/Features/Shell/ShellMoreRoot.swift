import SwiftUI
import FiestaBoardKit

/// Canonical More hierarchy. Later-slice operations are gated until their real flows exist.
struct ShellMoreRoot<Account: View, Hubs: View, About: View>: View {
    let hubName: String
    let host: String
    let username: String?
    let savedCount: Int
    let openDisplays: () -> Void
    @ViewBuilder let account: () -> Account
    @ViewBuilder let hubs: () -> Hubs
    @ViewBuilder let about: () -> About
    @Environment(\.colorScheme) private var appearance
    private var palette: ShellPalette { .init(appearance: appearance) }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hubName).font(.headline)
                    Text(host).font(.subheadline).foregroundStyle(.secondary)
                }
            }.listRowBackground(palette.card)
            Section {
                NavigationLink(destination: account) {
                    Label(username ?? "Account", systemImage: "person.crop.circle")
                }
            }.listRowBackground(palette.card)
            Section {
                Button {} label: { Label("FiestaBot", systemImage: "sparkles") }.disabled(true)
            }.listRowBackground(palette.card)
            Section("Hub · " + hubName) {
                Button {} label: { Label("Network", systemImage: "wifi") }.disabled(true)
                Button {} label: { Label("AI provider", systemImage: "sparkles") }.disabled(true)
                Button {} label: { Label("System & backups", systemImage: "externaldrive") }.disabled(true)
                Button {} label: { Label("Language & time", systemImage: "clock") }.disabled(true)
                NavigationLink(destination: hubs) {
                    LabeledContent { Text("\(savedCount) saved") } label: { Label("Hubs", systemImage: "externaldrive.connected.to.line.below") }
                }.accessibilityIdentifier("shellHubs")
            }.listRowBackground(palette.card)
            Section("Manage") {
                Button(action: openDisplays) { Label("Displays", systemImage: "rectangle.on.rectangle") }
                Button {} label: { Label("Integrations", systemImage: "puzzlepiece.extension") }.disabled(true)
            }.listRowBackground(palette.card)
            Section("Help") { NavigationLink("About", destination: about) }.listRowBackground(palette.card)
        }
        .scrollContentBackground(.hidden).background(palette.background)
        .navigationTitle("More")
    }
}

struct ShellHubsView: View {
    let hubs: [SavedServer]
    let activeDeployment: String
    let busy: Bool
    let select: (SavedServer) -> Void
    let add: () -> Void
    let forget: (SavedServer) -> Void
    var notice: String? = nil
    @State private var removing: SavedServer?
    @Environment(\.colorScheme) private var appearance
    private var palette: ShellPalette { .init(appearance: appearance) }
    var body: some View {
        List {
            Section {
                Text("Saved hubs on this device. Tap one to switch.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(hubs) { hub in
                    Button { select(hub) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(hub.alias.isEmpty ? hub.deployment.description : hub.alias)
                                Text(hub.deployment.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if hub.deployment.description == activeDeployment {
                                Label("Active", systemImage: "checkmark").font(.caption)
                            }
                        }
                    }.disabled(busy)
                        .contextMenu {
                            Button("Switch to " + hubName(hub)) { select(hub) }.disabled(busy)
                            Button("Forget hub…", role: .destructive) { removing = hub }.disabled(busy)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Forget", role: .destructive) { removing = hub }.disabled(busy)
                        }
                }
            } header: { Text("Saved hubs") }
                footer: { Text("Each hub keeps its own sign-in and selected display.") }
                .listRowBackground(palette.card)
            Section {
                Button("Add a hub", action: add).disabled(busy).accessibilityIdentifier("shellAddHub")
            }
                .listRowBackground(palette.card)
            if let notice {
                Section { Text(notice).font(.callout).accessibilityIdentifier("shellHubNotice") }
                    .listRowBackground(palette.card)
            }
        }
        .scrollContentBackground(.hidden).background(palette.background)
        .navigationTitle("Hubs")
        .confirmationDialog("Forget \(removing.map(hubName) ?? "hub")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Sign out and forget", role: .destructive) {
                    if let hub = removing { forget(hub) }
                    removing = nil
                }.accessibilityIdentifier("shellConfirmForgetHub")
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                Text("Sign out of this hub and remove it from this device. To use it again, add it and sign in. If the hub cannot be reached, its session may remain active there.")
            }
    }
    private func hubName(_ hub: SavedServer) -> String { hub.alias.isEmpty ? hub.deployment.description : hub.alias }
}
