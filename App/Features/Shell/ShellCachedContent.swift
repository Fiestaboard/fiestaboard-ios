import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// Read-only cached presentation. `cache:*` are DEBUG measurement keys, not Figma node IDs.
struct ShellCachedContent: View {
    let snapshot: ShellSnapshot
    let route: ShellTab
    let offline: Bool
    var body: some View {
        Group {
            if route == .pages {
                List(snapshot.pages) { page in
                    Text(page.name).figmaNode("cache:page-" + page.id, label: page.name)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(snapshot.displayName).font(.title)
                        if let detail = snapshot.board {
                            BoardViewport(frame: BoardFrame(detail), model: DisplayModel(summary: BoardSummaryFields(detail.summary), stored: nil))
                                .figmaNode("cache:board", label: detail.text)
                        }
                    }.padding().opacity(0.6)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if offline {
                ShellConnectionView(state: .offline, hub: "", retry: {})
                    .figmaNode("cache:offline", label: "You're offline")
            } else {
                Text("Updating…").font(.callout).padding().figmaNode("cache:updating", label: "Updating…")
            }
        }
        .navigationTitle(route.rawValue)
    }
}
