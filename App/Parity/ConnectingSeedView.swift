#if DEBUG
import SwiftUI

/// I2 deterministic seed only; I6 owns saved-hub state and live routing.
/// Body measurements and Light colours: Figma 362:19966, saved in
/// scripts/parity/figma/figma-connecting-362-20090.md. Chrome is native.
/// `seed:*` are measurement keys, not invented Figma child node IDs.
struct ConnectingSeedView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                            Text("Connecting to Maya's FiestaPi…")
                                .font(.system(size: 15)).foregroundStyle(Color(red: 74/255, green: 71/255, blue: 68/255))
                        }
                        .padding(.leading, 4).frame(height: 20)
                        .figmaNode("seed:connecting", label: "Connecting to Maya's FiestaPi…")
                        skeleton("seed:board", width: 370, height: 150)
                        skeleton("seed:line-1", width: 220, height: 18)
                        skeleton("seed:line-2", width: 300, height: 18)
                        skeleton("seed:action", width: 160, height: 44)
                        ForEach(1...3, id: \.self) { index in
                            skeleton("seed:row-\(index)", width: 370, height: 56)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(red: 241/255, green: 236/255, blue: 230/255))
                    .navigationTitle("Home").navigationBarTitleDisplayMode(.large)
                }
            }
            Tab("Pages", systemImage: "doc.on.doc") { Color.clear }
            Tab("Schedule", systemImage: "calendar") { Color.clear }
            Tab("Displays", systemImage: "display") { Color.clear }
            Tab("More", systemImage: "ellipsis") { Color.clear }
        }
        .preferredColorScheme(.light)
        .tint(Color(red: 137/255, green: 87/255, blue: 0))
        .figmaNode("362:20090", coversSafeArea: true)
        .transaction { $0.disablesAnimations = true }
    }

    private func skeleton(_ key: String, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(red: 236/255, green: 230/255, blue: 223/255))
            .frame(width: width, height: height)
            .figmaNode(key)
            .accessibilityHidden(true)
    }
}
#endif
