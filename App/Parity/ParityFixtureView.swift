#if DEBUG
import SwiftUI

/// Test-only, no model, discovery, persisted connection or network.
struct ParityFixtureView: View {
    enum Kind: String {
        case glass, connecting
        static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> Self? {
            defaults.string(forKey: "fiestaboard.parityFixture").flatMap(Self.init(rawValue:))
        }
    }
    let kind: Kind

    @ViewBuilder var body: some View {
        if kind == .connecting {
            ConnectingSeedView()
        } else {
            glassFixture
        }
    }

    private var glassFixture: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<Int(ceil(size.width / 40)), id: \.self) { index in
                        (index.isMultiple(of: 2) ? Color(red: 1, green: 0, blue: 0) : Color(red: 0, green: 0, blue: 1)).frame(width: 40)
                    }
                }.accessibilityHidden(true)
                Text("Parity fixture")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .figmaNode("parity:title", label: "Parity fixture", identify: true)
                    .placed(x: 32, y: 100)
                Color.clear
                    .frame(width: size.width - 64, height: 200)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
                    .accessibilityElement()
                    .accessibilityLabel("Glass panel")
                    .figmaNode("parity:glass", label: "Glass panel", identify: true)
                    .placed(x: 32, y: 260)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .transaction { $0.disablesAnimations = true }
    }
}

private extension View {
    /// Place siblings outside the tagged element, preserving its AX bounds.
    func placed(x: CGFloat, y: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 1, height: y)
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: x, height: 1)
                self
            }
        }.accessibilityElement(children: .contain)
    }
}
#endif
