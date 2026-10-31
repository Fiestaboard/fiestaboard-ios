import Foundation

/// The `/v1/boards` fields a display model is resolved from. The renderer has
/// no networking dependency, so the app maps its API type onto this.
public struct BoardSummaryFields: Sendable, Equatable {
    public var deviceType: String?
    public var rows: Int
    public var cols: Int
    public var deviceModel: String?
    public var charset: String?
    public var output: String?
    public init(deviceType: String?, rows: Int, cols: Int, deviceModel: String? = nil,
                charset: String? = nil, output: String? = nil) {
        self.deviceType = deviceType; self.rows = rows; self.cols = cols
        self.deviceModel = deviceModel; self.charset = charset; self.output = output
    }
}

public enum LedFont: String, Sendable, Equatable {
    case f3x5 = "3x5", f5x7 = "5x7"
    public var glyphWidth: Int { self == .f3x5 ? 3 : 5 }
    public var glyphHeight: Int { self == .f3x5 ? 5 : 7 }
}

public struct LedLayout: Sendable, Equatable {
    public var tileGapFill: Bool
    public var blockPadding: Int
    public static let none = LedLayout(tileGapFill: false, blockPadding: 0)
    public init(tileGapFill: Bool, blockPadding: Int) { self.tileGapFill = tileGapFill; self.blockPadding = blockPadding }
}

public struct LedAppearance: Sendable, Equatable {
    public enum PixelShape: String, Sendable { case round, square }
    public var pixelShape: PixelShape
    public var dotRatio: Double
    public var offColor: UInt32
    public var substrateColor: UInt32
    public var bezel: UInt32
    public static let square = LedAppearance(pixelShape: .square, dotRatio: 0.82, offColor: 0x171717, substrateColor: 0x0a0a0a, bezel: 0x050505)
    public static let round = LedAppearance(pixelShape: .round, dotRatio: 0.72, offColor: 0x171717, substrateColor: 0x0a0a0a, bezel: 0x050505)
}

/// One decoded description of how a board looks (design/board-display-visuals.md §2.2).
///
/// Decoded from the merge of a `/v1/boards` entry and the matching
/// `/settings/board` entry. Every appearance field is optional and defaulted
/// from `device_model`; an unknown model draws as a split-flap of the board's
/// `rows × cols` — it never throws and never fails (`device-preview.ts:6-11`).
public struct DisplayModel: Sendable, Equatable {
    public enum Technology: Sendable, Equatable { case splitFlap, ledMatrix }
    public enum Geometry: Sendable, Equatable {
        case cells(rows: Int, cols: Int), noteArray(wide: Int, tall: Int), panel(rows: Int, cols: Int), pixels(w: Int, h: Int)
    }
    public enum ColorKind: Sendable, Equatable { case tiles, rgb, monochrome(hex: UInt32) }

    public var modelID: String?
    public var technology: Technology
    public var geometry: Geometry
    public var color: ColorKind
    public var code62: Code62Glyph
    public var boardColor: BoardColor
    public var font: LedFont
    public var ledLayout: LedLayout
    public var appearance: LedAppearance
    /// Character grid (derived from pixels and font for LED models).
    public var rows: Int
    public var cols: Int
    /// True when the model id was not recognised and no spec was sent.
    public var isFallback: Bool

    /// Flap boards keep their case only on LED charsets.
    public var preservesCase: Bool { technology == .ledMatrix }

    /// Note-array seams apply to note arrays only.
    public var seams: BoardLayout.NoteSeams? {
        if case .noteArray(let wide, let tall) = geometry, wide * tall > 1 { return .notes }
        return nil
    }

    public var flapPalette: FlapPalette {
        let base = FlapPalette.forBoard(boardColor)
        if case .monochrome(let hex) = color { return base.monochrome(hex) }
        return base
    }

    /// Known built-in models (FiestaUI `DEVICE_MODELS`, `devices.js:129-236`).
    static let ledModels: [String: (w: Int, h: Int, font: LedFont, color: ColorKind, look: LedAppearance)] = [
        "divoom_pixoo64": (64, 64, .f3x5, .rgb, .square),
        "ulanzi_tc001_awtrix": (32, 8, .f3x5, .rgb, .square),
        "wled_32x32": (32, 32, .f3x5, .rgb, .round),
        "hub75_64x32": (64, 32, .f5x7, .rgb, .round),
        "hub75_64x64": (64, 64, .f5x7, .rgb, .round),
        "hub75_128x64": (128, 64, .f5x7, .rgb, .round),
        "max7219_4in1": (32, 8, .f3x5, .monochrome(hex: 0xff3b1f), .round),
        "p10_hub12_32x16": (32, 16, .f5x7, .monochrome(hex: 0xff3b1f), .round),
        "tidbyt_tronbyt": (64, 32, .f5x7, .rgb, .square),
    ]
    static let flapModels: Set<String> = ["vestaboard_flagship", "vestaboard_note", "vestaboard_note_array",
                                          "vestaboard_panel", "fiestapanel_split_flap"]
    static let flapTypes: Set<String> = ["flagship", "note", "note_array", "panel"]

    /// `summary` = /v1/boards entry; `stored` = matching /settings/board entry (may be nil).
    public init(summary: BoardSummaryFields, stored: [String: Any]?) {
        let stored = stored ?? [:]
        let modelID = (stored["device_model"] as? String) ?? summary.deviceModel
        let deviceType = (stored["device_type"] as? String) ?? summary.deviceType
        self.modelID = modelID
        boardColor = (stored["board_color"] as? String) == "white" ? .white : .black
        ledLayout = Self.layout(stored["led_layout"] as? [String: Any])
        isFallback = false

        let spec = stored["device_model_spec"] as? [String: Any]
        let specLed = (spec?["technology"] as? String) == "led_matrix"
        let geometrySpec = spec?["geometry"] as? [String: Any]
        let builtIn = modelID.flatMap { Self.ledModels[$0] }

        if specLed || (spec == nil && builtIn != nil) {
            technology = .ledMatrix
            let w = Self.int(geometrySpec?["width"]) ?? builtIn?.w ?? 64
            let h = Self.int(geometrySpec?["height"]) ?? builtIn?.h ?? 64
            geometry = .pixels(w: max(1, w), h: max(1, h))
            let colorSpec = spec?["color"] as? [String: Any]
            if let colorSpec {
                if (colorSpec["kind"] as? String) == "monochrome",
                   let hex = (colorSpec["color"] as? String).flatMap(Self.hex) {
                    color = .monochrome(hex: hex)
                } else { color = .rgb }
            } else { color = builtIn?.color ?? .rgb }
            let layoutOptions = spec?["layoutOptions"] as? [String: Any]
            let requested = (layoutOptions?["font"] as? String) ?? (stored["led_font"] as? String)
            let specFont = (spec?["font"] as? String).flatMap(LedFont.init(rawValue:))
            font = requested.flatMap(LedFont.init(rawValue:)) ?? specFont ?? builtIn?.font ?? .f3x5
            var look = builtIn?.look ?? .round
            if let appearance = spec?["appearance"] as? [String: Any] {
                if let shape = (appearance["pixelShape"] as? String).flatMap(LedAppearance.PixelShape.init(rawValue:)) {
                    look = shape == .square ? .square : .round
                }
                if let ratio = appearance["dotRatio"] as? Double { look.dotRatio = ratio }
                if let off = (appearance["offColor"] as? String).flatMap(Self.hex) { look.offColor = off }
                if let substrate = (appearance["substrateColor"] as? String).flatMap(Self.hex) { look.substrateColor = substrate }
                if let bezel = (appearance["bezel"] as? String).flatMap(Self.hex) { look.bezel = bezel }
            }
            appearance = look
            // ledGridLayout (FiestaUI led-matrix.js:76-87), spacing 1/1.
            rows = max(1, (h + 1) / (font.glyphHeight + 1))
            cols = max(1, (w + 1) / (font.glyphWidth + 1))
            code62 = .heart
            return
        }

        technology = .splitFlap
        color = .tiles
        font = .f5x7
        appearance = .round
        let kind = (geometrySpec?["kind"] as? String)
        let known = modelID.map { Self.flapModels.contains($0) } ?? false
        let typeKnown = deviceType.map { Self.flapTypes.contains($0) } ?? false
        if deviceType == "note_array" || kind == "note_array" || modelID == "vestaboard_note_array" {
            let wide = max(1, min(8, Self.int(stored["notes_wide"]) ?? max(1, summary.cols / 15)))
            let tall = max(1, min(8, Self.int(stored["notes_tall"]) ?? max(1, summary.rows / 3)))
            geometry = .noteArray(wide: wide, tall: tall)
            rows = tall * 3; cols = wide * 15
        } else if deviceType == "panel" || modelID == "vestaboard_panel" || modelID == "fiestapanel_split_flap" {
            let r = Self.int(stored["grid_rows"]) ?? summary.rows
            let c = Self.int(stored["grid_cols"]) ?? summary.cols
            geometry = .panel(rows: max(1, r), cols: max(1, c))
            rows = max(1, r); cols = max(1, c)
        } else {
            let r = Self.int(geometrySpec?["rows"]) ?? summary.rows
            let c = Self.int(geometrySpec?["cols"]) ?? summary.cols
            geometry = .cells(rows: max(1, r), cols: max(1, c))
            rows = max(1, r); cols = max(1, c)
        }
        rows = min(rows, BoardFrame.maxDimension); cols = min(cols, BoardFrame.maxDimension)
        isFallback = spec == nil && !known && !(modelID == nil && typeKnown)
        // Code 62 (FiestaUI resolveCode62Glyph): note, note array and panel always
        // draw the heart; a Flagship draws its configured glyph (degree default).
        let configured = (stored["code62_glyph"] as? String).flatMap(Code62Glyph.init(rawValue:))
            ?? (summary.charset == "vestaboard_v2" && deviceType == "flagship" ? .heart : nil)
        switch geometry {
        case .noteArray, .panel: code62 = .heart
        default:
            code62 = (deviceType == "note" || modelID == "vestaboard_note") ? .heart : (configured ?? .degree)
        }
    }

    /// A model for a bare grid (editor stages, tests).
    public static func flap(rows: Int, cols: Int, deviceType: String = "flagship",
                            boardColor: BoardColor = .black, code62: Code62Glyph = .degree) -> DisplayModel {
        var stored: [String: Any] = ["board_color": boardColor.rawValue, "code62_glyph": code62.rawValue]
        if deviceType == "note_array" { stored["notes_wide"] = max(1, cols / 15); stored["notes_tall"] = max(1, rows / 3) }
        if deviceType == "panel" { stored["grid_rows"] = rows; stored["grid_cols"] = cols }
        return DisplayModel(summary: BoardSummaryFields(deviceType: deviceType, rows: rows, cols: cols), stored: stored)
    }

    static func layout(_ value: [String: Any]?) -> LedLayout {
        guard let value else { return .none }
        let gap = (value["tile_gap"] as? String) ?? (value["tileGap"] as? String)
        let padding = int(value["block_padding"]) ?? int(value["blockPadding"]) ?? 0
        return LedLayout(tileGapFill: gap == "fill", blockPadding: max(0, min(1, padding)))
    }
    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double, value.isFinite { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
    static func hex(_ string: String) -> UInt32? {
        let cleaned = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard cleaned.count == 6 else { return nil }
        return UInt32(cleaned, radix: 16)
    }
}
