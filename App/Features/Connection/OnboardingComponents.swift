import SwiftUI
import FiestaBoardKit
import FiestaBoardRender

/// Shared generated colours and native touch controls for the onboarding flow.
struct OnboardingPalette {
    let appearance: ColorScheme
    func color(_ name: String) -> Color {
        let token = (appearance == .dark ? FiestaTokenValues.Dark.all : FiestaTokenValues.Light.all)[name]!
        return Color(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}

struct OnboardingAction: View {
    let title: String
    var primary = true
    var leadingImage: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var appearance
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    var body: some View {
        if primary {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                .tint(palette.color("primary")).foregroundStyle(palette.color("primary-foreground"))
                .frame(minHeight: PlatformIOSValues.Touch.buttonHeight)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
                .frame(minHeight: PlatformIOSValues.Touch.buttonHeight)
        }
    }
    private var label: some View {
        HStack(spacing: 8) {
            if let leadingImage { Image(leadingImage).renderingMode(.template).accessibilityHidden(true) }
            Text(title)
        }.frame(maxWidth: .infinity)
    }
}

struct OnboardingNotice: View {
    let title: String
    let detail: String
    var symbol = "info.circle"
    var tone = "info"
    @Environment(\.colorScheme) private var appearance
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(palette.color(tone)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.color(tone).opacity(0.09), in: RoundedRectangle(cornerRadius: FiestaTokenValues.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: FiestaTokenValues.Radius.card).stroke(palette.color(tone), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingPrivacyNote: View {
    @Environment(\.colorScheme) private var appearance
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("OnboardingPrivacy").renderingMode(.template).foregroundStyle(palette.color("success")).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your data stays on your network").font(.headline)
                Text("This app talks straight to your FiestaBoard hub. There is no FiestaBoard cloud account. Keys you enter are saved on your hub, not in this app.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.color("card"), in: RoundedRectangle(cornerRadius: FiestaTokenValues.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: FiestaTokenValues.Radius.card).stroke(palette.color("border")))
    }
}

struct OnboardingHubCard: View {
    let name: String
    let address: String
    @Environment(\.colorScheme) private var appearance
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    var body: some View {
        HStack(spacing: 12) {
            Image("OnboardingHub").renderingMode(.template).padding(8)
                .background(palette.color("muted"), in: RoundedRectangle(cornerRadius: FiestaTokenValues.Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(address).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.color("card"), in: RoundedRectangle(cornerRadius: 26))
            .accessibilityElement(children: .contain).accessibilityIdentifier("onboardingHub")
    }
}

struct OnboardingFieldStyle: ViewModifier {
    var verticalPadding: CGFloat = 10
    @Environment(\.colorScheme) private var appearance
    func body(content: Content) -> some View {
        content.padding(.horizontal, 12).padding(.vertical, verticalPadding)
            .frame(minHeight: PlatformIOSValues.Touch.minTarget)
            .background(OnboardingPalette(appearance: appearance).color("background"))
            .overlay(RoundedRectangle(cornerRadius: FiestaTokenValues.Radius.control)
                .stroke(OnboardingPalette(appearance: appearance).color("input")))
    }
}

/// Original 720×400 backdrop geometry; it tiles on iPad without scaling the flaps.
struct OnboardingBackdrop: View {
    var tiled = false
    @Environment(\.colorScheme) private var appearance
    var body: some View {
        GeometryReader { geometry in
            let columns = tiled ? max(1, Int(ceil((geometry.size.width + 130) / 720))) : 1
            let rows = tiled ? max(1, Int(ceil((geometry.size.height + 20) / 400))) : 1
            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        field.offset(x: tiled ? -130 + CGFloat(column) * 720 : (geometry.size.width - 720) / 2,
                                     y: tiled ? -20 + CGFloat(row) * 400 : -96)
                    }
                }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
    private var field: some View {
        Canvas { context, _ in
            let model = DisplayModel(summary: .init(deviceType: "flagship", rows: 6, cols: 22), stored: nil)
            for row in OnboardingBackdropArtwork.rows {
                for (column, cell) in row.cells.enumerated() {
                    FlapTilePainter.paint(code: BoardTables.code(for: cell), model: model,
                        in: CGRect(x: row.x + Double(column) * 27.2, y: row.y, width: 22.1, height: 30.6), context: &context)
                }
            }
        }.frame(width: 720, height: 400)
            .mask(Image("OnboardingBackdropMask"))
            .opacity(appearance == .dark ? 0.28 : 0.16)
    }
}
