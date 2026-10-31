import SwiftUI
import FiestaBoardEditorState

/// The single status word beside Save (PLAN B25).
struct SaveStatusChip: View {
    var status: SaveStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(status.label).font(.caption.weight(.medium)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Save status")
        .accessibilityValue(status.label)
        .accessibilityIdentifier("saveStatus")
    }

    private var tint: Color {
        switch status {
        case .saved: .green
        case .unsaved: .orange
        case .saving: .blue
        case .conflict, .unknown: .red
        }
    }
}
