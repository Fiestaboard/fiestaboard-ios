import SwiftUI
import FiestaBoardRender

/// A production SwiftUI adapter for generated values; native glass remains system-owned.
struct ShellPalette {
    let appearance: ColorScheme
    var background: Color { color(appearance == .dark ? FiestaTokenValues.Dark.background : FiestaTokenValues.Light.background) }
    var card: Color { color(appearance == .dark ? FiestaTokenValues.Dark.card : FiestaTokenValues.Light.card) }
    var tint: Color { color(appearance == .dark ? FiestaTokenValues.Dark.brand : FiestaTokenValues.Light.brand) }
    var skeleton: Color { color(appearance == .dark ? FiestaTokenValues.Dark.accent : FiestaTokenValues.Light.accent) }
    private func color(_ token: TokenColor) -> Color {
        Color(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}
