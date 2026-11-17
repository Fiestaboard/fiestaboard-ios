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
                NavigationLink(destination: account) {
                    Label(username ?? "Account", systemImage: "person.crop.circle")
                }
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
    @Environment(\.colorScheme) private var appearance
    private var palette: ShellPalette { .init(appearance: appearance) }
    var body: some View {
        List {
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
                }
                Button("Add a hub", action: add).accessibilityIdentifier("shellAddHub")
            } footer: { Text("Each hub keeps its own sign-in and selected display.") }
                .listRowBackground(palette.card)
        }
        .scrollContentBackground(.hidden).background(palette.background)
        .navigationTitle("Hubs")
    }
}
