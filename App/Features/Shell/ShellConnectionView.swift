import SwiftUI
import FiestaBoardAppState
import FiestaBoardRender

/// Live state presentation. Native chrome and SF type retain the program's standing waivers.
struct ShellConnectionView: View {
    let state: ShellConnection.Presentation
    let hub: String
    let retry: () -> Void
    @Environment(\.colorScheme) private var appearance
    private var palette: ShellPalette { ShellPalette(appearance: appearance) }
    var body: some View {
        switch state {
        case .online: EmptyView()
        case .offline:
            Label("You're offline. Connect to Wi-Fi or cellular to reach your hub.", systemImage: "wifi.slash")
                .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary).accessibilityIdentifier("shellOffline")
        case .unreachable:
            ContentUnavailableView {
                Label("Can't reach " + hub, systemImage: "network.slash")
            } description: {
                Text("Check that your hub is on and you're on the same network, or use its remote address.")
            } actions: {
                Button("Try again", action: retry)
            }.background(palette.background.ignoresSafeArea()).accessibilityIdentifier("shellUnreachable")
        case .connecting(let still, _):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if still {
                        Label("Still connecting. Check that your hub is on and you're on the same network.", systemImage: "info.circle")
                            .font(.callout).padding().frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        HStack(spacing: 10) {
                            TacoLoader(size: .inline)
                            Text("Connecting to " + hub + "…").font(.subheadline)
                                .figmaNode("shell:connecting-label", label: "Connecting to " + hub)
                        }.padding(.leading, 4)
                    }
                    RoundedRectangle(cornerRadius: 8).fill(palette.skeleton).frame(height: 150).accessibilityHidden(true)
                    RoundedRectangle(cornerRadius: 8).fill(palette.skeleton).frame(maxWidth: 220).frame(height: 18).accessibilityHidden(true)
                    RoundedRectangle(cornerRadius: 8).fill(palette.skeleton).frame(maxWidth: 300).frame(height: 18).accessibilityHidden(true)
                    RoundedRectangle(cornerRadius: 8).fill(palette.skeleton).frame(width: 160, height: 44).accessibilityHidden(true)
                    ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 8).fill(palette.skeleton).frame(height: 56).accessibilityHidden(true) }
                }.padding(.horizontal, 16).padding(.top, 8)
            }.background(palette.background).accessibilityIdentifier("shellConnecting")
        }
    }
}
