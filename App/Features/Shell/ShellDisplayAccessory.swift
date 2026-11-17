import SwiftUI
import FiestaBoardKit

struct ShellDisplayAccessory: View {
    #if DEBUG
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    #endif
    let displays: [BoardSummary]
    let selectedID: String?
    let nowShowing: String?
    let hubName: String
    let host: String
    let disabled: Bool
    let select: (String) -> Void
    var body: some View {
        Menu {
            Section { Text(hubName); Text(host) }
            ForEach(displays) { display in
                Button { select(display.id) } label: {
                    if display.id == selectedID { Label(display.name, systemImage: "checkmark") }
                    else { Text(display.name) }
                }.disabled(disabled)
            }
        } label: {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                VStack(alignment: .leading) {
                    Text("Now showing · " + (nowShowing ?? "No page selected")).font(.subheadline)
                    Text(displays.first { $0.id == selectedID }?.name ?? "No display selected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }.padding(.horizontal)
        }.accessibilityIdentifier("shellDisplaySwitcher")
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            Color.clear.frame(width: 1, height: 1).accessibilityElement()
                .accessibilityLabel("Native accessory placement")
                .accessibilityValue(placement == .inline ? "inline" : placement == .expanded ? "expanded" : "none")
                .accessibilityIdentifier("shellTabAccessoryPlacement")
        }
        #endif
    }
}
