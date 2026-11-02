import Foundation
import FiestaBoardKit
import FiestaBoardRender

/// The out-of-sync banner's faces (B9; web `board-out-of-sync-banner.tsx`,
/// design/board-display-visuals.md §3.2), from `/board/current-message`.
public struct OutOfSync: Sendable, Equatable {
    public enum Face: String, Sendable, Equatable { case outOfSync = "out-of-sync", overwritten, kept }
    public let face: Face
    /// The frame "Save as page" keeps: what the board shows (out-of-sync) or the
    /// held external frame (kept). The overwritten face has none.
    public let grid: [[Int]]?
    /// ISO time for the overwritten / kept faces.
    public let detectedAt: String?

    /// The live faces win: what is on the board now is what the user sees.
    /// Hidden during silence (FiestaBoard leaves the board alone on purpose).
    public static func make(_ message: CurrentBoardMessage?, silenceActive: Bool) -> OutOfSync? {
        guard let message, !silenceActive else { return nil }
        let characters = message.characters, expected = message.expectedCharacters
        if let characters, let expected, characters != expected {
            return OutOfSync(face: .outOfSync, grid: characters, detectedAt: nil)
        }
        if let at = message.overwrittenAt, !at.isEmpty {
            return OutOfSync(face: .overwritten, grid: nil, detectedAt: at)
        }
        if let external = message.externalCharacters, external != expected {
            return OutOfSync(face: .kept, grid: external, detectedAt: message.externalDetectedAt)
        }
        return nil
    }

    /// Restore is offered on the live faces; Dismiss on the kept face.
    public var offersRestore: Bool { face != .kept }
    public var offersSave: Bool { grid != nil }
    public var offersDismiss: Bool { face == .kept }

    public func title(time: String) -> String {
        face == .kept ? "Another app wrote to this board at \(time)" : "Another app changed this board"
    }
    public func detail(time: String) -> String {
        switch face {
        case .outOfSync: "FiestaBoard will replace it the next time your page updates. Save it as a page to keep it."
        case .overwritten: "Detected: \(time). FiestaBoard can't see what this display shows now, so there's nothing to save. Restore puts your page back."
        case .kept: "FiestaBoard has since put your page back. You can still save what the other app wrote."
        }
    }
    public static let holdPaused = "This display is paused, so Restore won't send anything until you resume it."

    /// A short local time for an ISO 8601 stamp ("9:12 AM"); the raw text if unparseable.
    public static func displayTime(_ iso: String?, timeZone: TimeZone = .current) -> String {
        guard let iso else { return "an unknown time" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? { parser.formatOptions = [.withInternetDateTime]; return parser.date(from: iso) }()
        guard let date else { return iso }
        let out = DateFormatter(); out.timeZone = timeZone; out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "h:mm a"
        return out.string(from: date)
    }
}

/// A board frame as page template rows (web `boardCharactersToTemplate`):
/// characters as text, colour codes as `{{red}}` tiles, code 62 as the board's glyph.
public enum BoardTemplate {
    public static func rows(_ codes: [[Int]], code62: Code62Glyph = .degree) -> [String] {
        codes.map { row in
            var line = ""
            for code in row {
                switch BoardTables.cell(forCode: code, code62: code62) {
                case .blank: line += " "
                case .character(let c): line.append(c)
                case .color(let color): line += "{{\(color.rawValue)}}"
                }
            }
            return line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
    }

    /// "From board Nov 1, 9:12 AM" (web `externalPageName`).
    public static func pageName(now: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d, h:mm a"
        return "From board " + f.string(from: now)
    }
}
