import SwiftUI
import FiestaBoardAppState

/// Home's status content stays separate from native navigation and tab glass.
struct HomeStatusSummary: View {
    let presentation: HomePresentation
    let displayName: String
    let pageName: String
    var previewing = false
    let canChangePage: Bool
    let changePage: () -> Void
    let canCancel: Bool
    let cancel: () -> Void
    @Environment(\.colorScheme) private var appearance
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let palette = ShellPalette(appearance: appearance)
        let isOverride = !previewing && presentation.modeLabel == "Override"
        VStack(alignment: .leading, spacing: 8) {
            let modeLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            modeLayout {
                Text(previewing ? "Preview" : presentation.modeLabel)
                    .font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(isOverride ? palette.primaryForeground : palette.foreground)
                    .background(isOverride ? palette.primary : palette.skeleton, in: Capsule())
                    .accessibilityIdentifier("modeBadge")
                if !previewing && presentation.modeLabel == "Collection" {
                    Image(systemName: "rectangle.stack").accessibilityLabel("Collection").accessibilityIdentifier("collectionBadge")
                }
                Text(previewing ? "Not sent yet" : "Now showing · \(displayName)").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(pageName).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nowShowingName")
            if !previewing, let remaining = presentation.overrideRemaining {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
                layout {
                    Label { Text(remaining) } icon: { Image(systemName: "clock").foregroundStyle(palette.tint) }
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("homeOverrideRemaining")
                    if !textSize.isAccessibilitySize { Spacer() }
                    if let expiry = presentation.overrideExpiresAt {
                        Text("until \(expiry.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("homeOverrideExpiry")
                    }
                }
                if let fraction = presentation.overrideRemainingFraction {
                    ProgressView(value: fraction).tint(palette.primary)
                        .accessibilityLabel("Override time remaining")
                        .accessibilityIdentifier("homeOverrideProgress")
                }
                if let expiry = presentation.overrideExpiresAt {
                    Text(presentation.overrideResumesSchedule
                        ? "Holds until \(expiry.formatted(date: .omitted, time: .shortened)), then Schedule resumes"
                        : "Override ends at \(expiry.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("homeOverrideExplanation")
                }
            } else if !previewing, let next = presentation.nextChange {
                HStack(spacing: 4) {
                    Text("Until \(next.at.formatted(date: .omitted, time: .shortened))")
                    if let name = next.pageName { Text("· then \(name)") }
                }.font(.subheadline).foregroundStyle(.secondary)
            }
            let actions = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            actions {
                Button(action: changePage) { Text("Change Page").frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true) }
                    .disabled(!canChangePage).accessibilityIdentifier("changePage")
                if !previewing, presentation.overrideRemaining != nil {
                    Button(action: cancel) { Text("Cancel override").frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true) }
                        .disabled(!canCancel).accessibilityLabel("Cancel override")
                        .accessibilityValue(canCancel ? "" : "Unavailable")
                        .accessibilityIdentifier("overrideCancel")
                }
            }.buttonStyle(.bordered).controlSize(.large).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
