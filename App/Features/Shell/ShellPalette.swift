import SwiftUI
import FiestaBoardRender

/// A production SwiftUI adapter for generated values; native glass remains system-owned.
struct ShellPalette {
    let appearance: ColorScheme
    var background: Color { color(appearance == .dark ? FiestaTokenValues.Dark.background : FiestaTokenValues.Light.background) }
    var card: Color { color(appearance == .dark ? FiestaTokenValues.Dark.card : FiestaTokenValues.Light.card) }
    var foreground: Color { color(appearance == .dark ? FiestaTokenValues.Dark.foreground : FiestaTokenValues.Light.foreground) }
    var info: Color { color(appearance == .dark ? FiestaTokenValues.Dark.info : FiestaTokenValues.Light.info) }
    var infoTint: Color { color(appearance == .dark ? PlatformIOSValues.Dark.tintInfo : PlatformIOSValues.Light.tintInfo) }
    var muted: Color { color(appearance == .dark ? FiestaTokenValues.Dark.muted : FiestaTokenValues.Light.muted) }
    var tint: Color { color(appearance == .dark ? FiestaTokenValues.Dark.brand : FiestaTokenValues.Light.brand) }
    var skeleton: Color { color(appearance == .dark ? FiestaTokenValues.Dark.accent : FiestaTokenValues.Light.accent) }
    private func color(_ token: TokenColor) -> Color {
        Color(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}
