import SwiftUI
import FiestaBoardAppState

/// Home's status content stays separate from native navigation and tab glass.
struct HomeStatusSummary: View {
    let presentation: HomePresentation
    let displayName: String
    let pageName: String
    let canCancel: Bool
    let cancel: () -> Void
    @Environment(\.colorScheme) private var appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(presentation.modeLabel)
                    .font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(ShellPalette(appearance: appearance).skeleton, in: Capsule())
                    .accessibilityIdentifier("modeBadge")
                if presentation.modeLabel == "Collection" {
                    Image(systemName: "rectangle.stack").accessibilityLabel("Collection").accessibilityIdentifier("collectionBadge")
                }
                Text("Now showing · \(displayName)").font(.caption).foregroundStyle(.secondary)
            }
            Text(pageName).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nowShowingName")
            if let remaining = presentation.overrideRemaining {
                HStack {
                    Label(remaining, systemImage: "timer").font(.subheadline)
                        .accessibilityIdentifier("homeOverrideRemaining")
                    Spacer()
                    Button("Cancel", action: cancel).buttonStyle(.bordered).controlSize(.large)
                        .disabled(!canCancel).accessibilityLabel("Cancel override")
                        .accessibilityValue(canCancel ? "" : "Unavailable")
                        .accessibilityIdentifier("overrideCancel")
                }
            } else if let next = presentation.nextChange {
                HStack(spacing: 4) {
                    Text("Until \(next.at.formatted(date: .omitted, time: .shortened))")
                    if let name = next.pageName { Text("· then \(name)") }
                }.font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
