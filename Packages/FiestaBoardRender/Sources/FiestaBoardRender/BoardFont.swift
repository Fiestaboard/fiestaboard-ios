// Vendored from fiestaboard-tvos@f1fc67d Sources/Render/BoardFont.swift. MIT: ThirdPartyNotices/FiestaBoardTV-MIT.txt.
// Mobile change: the face is loaded from this module's bundle, not Bundle.main.
import CoreText
import Foundation
import SwiftUI

/// The glyph face for board flaps.
///
/// Spline Sans Mono is FiestaUI's `--font-mono`, so using it here is what
/// makes the letterforms on the phone the same shapes as in the web viewer.
/// If registration fails the monospaced system face stands in rather than the
/// board going blank. OFL notice: ThirdPartyNotices/SplineSansMono-OFL.txt.
public enum BoardFont {

    public static let familyName = "Spline Sans Mono"

    private static let registration: Bool = {
        guard let url = RenderResources.url("SplineSansMono", "ttf") else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // Already registered by an earlier load counts as available.
        return isAvailable
    }()

    private static var isAvailable: Bool {
        let font = CTFontCreateWithName(familyName as CFString, 12, nil)
        return (CTFontCopyFamilyName(font) as String) == familyName
    }

    /// Register the bundled face. Idempotent; safe to call repeatedly.
    @discardableResult public static func registerIfNeeded() -> Bool { registration }

    public static func glyph(size: Double) -> Font {
        if registerIfNeeded() {
            return .custom(familyName, fixedSize: size).weight(.semibold)
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }
}

/// Resources live in one `RenderAssets` folder (a top-level `Resources` dir makes iOS installd read a shallow framework as a deep bundle) in both the SwiftPM target and the
/// XcodeGen framework (`App/PackageResources.swift` supplies `Bundle.module`).
public enum RenderResources {
    public static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "RenderAssets")
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
    public static func data(_ name: String, _ ext: String) -> Data? {
        url(name, ext).flatMap { try? Data(contentsOf: $0) }
    }
}

extension BoardColor {
    public var swiftUI: Color { Color(boardHex: hex) }
}

extension Color {
    /// `#rrggbb`. Board pigments and appearance tokens are the only source, so
    /// the parse is strict and falls back to board black.
    public init(boardHex hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255)
            return
        }
        self.init(rgb: value)
    }
    public init(rgb value: UInt32) {
        self = Color(.sRGB, red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255, opacity: 1)
    }
}
