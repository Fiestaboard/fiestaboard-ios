import Foundation
import FiestaBoardKit
import FiestaBoardRender

/// Badges on a Displays card (B10, web `displays-page.tsx`): only what the
/// server's facts imply, in this order.
public enum DisplayBadge: String, Sendable, Equatable, CaseIterable {
    case unavailable = "Unavailable"
    case paused = "Paused"
    case fiestaPanel = "FiestaPanel"
    case connected = "Connected"
    case notConfigured = "Not configured"

    public static func make(summary: BoardSummary, runtime: BoardRuntimeStatus?) -> [DisplayBadge] {
        var out: [DisplayBadge] = []
        if runtime?.error?.isEmpty == false || runtime?.configured == false { out.append(.unavailable) }
        if runtime?.paused ?? summary.paused { out.append(.paused) }
        if summary.output == "fiestapanel" { out.append(.fiestaPanel) }
        switch runtime?.outputStatus?.state {
        case "connected"?: if !out.contains(.unavailable) { out.append(.connected) }
        case "not_configured"?: out.append(.notConfigured)
        default: break
        }
        return out
    }
}

/// "Flagship • 6×22 • Black" (web words), and a readable output name.
public enum DisplayDescription {
    public static func line(summary: BoardSummary, model: DisplayModel) -> String {
        let type: String
        if model.technology == .ledMatrix {
            if case .pixels(let w, let h) = model.geometry { type = "LED \(w)×\(h)" } else { type = "LED" }
        } else {
            switch summary.deviceType {
            case "note": type = "Note"
            case "note_array": type = "Note Array"
            case "panel": type = "Panel"
            case "flagship": type = "Flagship"
            default: type = summary.deviceType.capitalized
            }
        }
        let color: String
        switch model.color {
        case .monochrome: color = "Single colour"
        case .rgb: color = "Full colour"
        case .tiles: color = model.boardColor == .white ? "White" : "Black"
        }
        return "\(type) • \(model.rows)×\(model.cols) • \(color)"
    }

    public static func output(_ id: String) -> String {
        switch id {
        case "vestaboard": "Vestaboard"
        case "fiestapanel": "FiestaPanel"
        case "divoom_pixoo": "Divoom Pixoo"
        default:
            id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }
}
