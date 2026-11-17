import SwiftUI
import FiestaBoardAppState
import FiestaBoardRender

struct ComposePreviewPanel: View {
    let projection: ComposePreviewProjection?
    let notice: ComposePreviewNotice
    let displayName: String
    let updating: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let projection {
                BoardViewport(frame: projection.frame, model: projection.model, fitLEDWidth: true)
                    .frame(minHeight: 100, maxHeight: 240)
                    .accessibilityLabel("Message preview for \(displayName)")
                    .accessibilityIdentifier("composeBoardPreview")
                    .transaction { $0.animation = nil }
            } else {
                ContentUnavailableView("Your preview appears here", systemImage: "rectangle.on.rectangle",
                    description: Text("Type a message to preview it on this display."))
                    .frame(minHeight: 100)
            }
            HStack(alignment: .firstTextBaseline) {
                Label(notice.label, systemImage: notice.state == .live ? "eye" : "clock")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("composePreviewState")
                if updating { ProgressView().accessibilityLabel("Updating preview") }
                Spacer(minLength: 0)
                if notice.state == .stale { Button("Retry", action: retry).font(.caption) }
            }
            if notice.clipped {
                Label("This display clips part of your message. The full text is kept below.", systemImage: "exclamationmark.triangle")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("composeClippingWarning")
            }
        }
    }
}
