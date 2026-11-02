import SwiftUI

/// How the page editor is shown (PLAN B29): on a wide window (iPad) it is a navigation
/// destination pushed in the Library's stack, never a page sheet; on a phone it covers the
/// screen, so the board gets the full height. Either way the editor keeps its Close item and
/// the same dirty-state confirmation; the back button stays hidden, so an edge swipe can't
/// drop unsaved work.
struct EditorPresentation<Editor: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var editor: () -> Editor
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.navigationDestination(isPresented: $isPresented) { editor() }
        } else {
            content.fullScreenCover(isPresented: $isPresented) { NavigationStack { editor() } }
        }
    }
}
