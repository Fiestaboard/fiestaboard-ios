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
    /// The idiom is chosen when the editor opens and kept while it is open: rotating a large
    /// phone to landscape (regular width) must not tear the editor down and rebuild it.
    @State private var pushes = false

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(get: { isPresented && pushes }, set: { if !$0 { isPresented = false } })) { editor() }
            .fullScreenCover(isPresented: Binding(get: { isPresented && !pushes }, set: { if !$0 { isPresented = false } })) { NavigationStack { editor() } }
            .onChange(of: isPresented, initial: true) { _, open in if open { pushes = sizeClass == .regular } }
            .onChange(of: sizeClass, initial: true) { _, size in if !isPresented { pushes = size == .regular } }
    }
}

/// True while a page editor is on screen. The app shell (iOS-R2's split view) can read it with
/// `.onPreferenceChange(EditorIsOpenKey.self)` and collapse the sidebar (`columnVisibility =
/// .detailOnly`) so the board gets the whole width on iPad (B29: "the board should grow").
struct EditorIsOpenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
