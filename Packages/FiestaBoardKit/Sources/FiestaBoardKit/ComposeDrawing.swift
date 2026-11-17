import Foundation

/// H3 facts are advertised by the actual output plugin. A baseline or unknown
/// source cannot acquire rich tools from a friendly device/model name.
public struct BoardDrawing: Codable, Equatable, Sendable {
    public struct Features: Codable, Equatable, Sendable {
        public let lowercase: Bool
        public let colorText: Bool
        public let background: Bool
        public let tiles: Bool
        public let icons: Bool
        public let rgb: Bool
        public let solidShapes: Bool
        public let pixels: Bool
        enum CodingKeys: String, CodingKey {
            case lowercase, background, tiles, icons, rgb, pixels
            case colorText = "color_text", solidShapes = "solid_shapes"
        }
    }
    public let source: String
    public let technology: String
    public let color: String
    public let monochrome: String?
    public let font: String?
    public let icons: [String]
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let features: Features
    enum CodingKeys: String, CodingKey {
        case source, technology, color, monochrome, font, icons, features
        case pixelWidth = "pixel_width", pixelHeight = "pixel_height"
    }
    public var isKnownDevice: Bool { source == "device" && ["split_flap", "led_matrix"].contains(technology) }
    public var allowsTextColor: Bool { isKnownDevice && technology == "led_matrix" && features.colorText }
    public var allowsTiles: Bool { isKnownDevice && features.tiles }
    public var allowedIcons: [String] {
        guard isKnownDevice, technology == "led_matrix", features.icons else { return [] }
        return icons.filter { !$0.isEmpty && $0.utf8.count <= 64 && $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 } }
    }
    /// Encode only the bounded public fields above; unknown server extensions
    /// never enter the local draft presentation descriptor.
    public func presentationData() throws -> Data { try JSONEncoder().encode(self) }
}

public struct ComposePreviewDiagnostics: Sendable {
    public struct Line: Decodable, Sendable {
        public let line: Int
        public let widest: Int
        public let cut: Bool
        public let rowsWanted: Int
        public let rowsShown: Int
        enum CodingKeys: String, CodingKey {
            case line, widest, cut
            case rowsWanted = "rows_wanted", rowsShown = "rows_shown"
        }
    }
    public let lines: [Line]
    public var hasClippedContent: Bool { lines.contains(where: \.cut) }
    public var maximumSourceWidth: Int? { lines.map(\.widest).max() }
    public var clippedLineNumbers: [Int] { lines.filter(\.cut).map(\.line) }
    public init(rawData: Data) throws {
        struct Diagnostics: Decodable { let lines: [Line] }
        struct Reply: Decodable { let diagnostics: Diagnostics }
        guard let value = try? JSONDecoder().decode(Reply.self, from: rawData), value.diagnostics.lines.count <= 512,
              value.diagnostics.lines.allSatisfy({ $0.line > 0 && $0.widest >= 0 && $0.rowsWanted >= 0 && $0.rowsShown >= 0 }) else { throw FiestaBoardError.invalidResponse }
        lines = value.diagnostics.lines
    }
}
