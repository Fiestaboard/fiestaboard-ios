import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// The server-reported frame of a board, drawn by the shared renderer.
/// A thin wrapper over `BoardFrameView`; appearance comes from the merged
/// `DisplayModel` when the caller has one (Home), else from the summary alone.
struct BoardOutputView: View {
    let board: BoardDetail
    var expected = false
    var model: DisplayModel?
    var size: BoardSize = .fit
    var animated = true
    var loading = false

    var body: some View {
        let model = model ?? DisplayModel(summary: BoardSummaryFields(board.summary), stored: nil)
        BoardFrameView(frame: BoardFrame(board, expected: expected), model: model, size: size,
                       animated: animated, loading: loading)
            .accessibilityLabel(expected ? "Expected output" : "Server-reported output")
    }
}
