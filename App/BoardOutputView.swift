import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

struct BoardOutputView: View {
    let board: BoardDetail
    var expected = false
    private var grid: [[Int]]? { expected ? board.expectedCharacters : board.characters }
    private var glyph: Code62Glyph {
        let note = ["vestaboard_note", "vestaboard_note_array"].contains(board.summary.deviceModel ?? "")
        return Code62Glyph.effective(deviceType: note ? "note" : board.summary.deviceType, configured: nil)
    }
    private var supported: Bool {
        guard board.renderingSupport == .flapGrid, let grid, grid.count == board.summary.rows,
              grid.allSatisfy({ $0.count == board.summary.cols }),
              grid.joined().allSatisfy({ (0...71).contains($0) }) else { return false }
        return board.summary.rows * board.summary.cols <= 4096
    }
    var body: some View {
        if supported, let grid {
            Canvas { context, size in
                let cellWidth = size.width / Double(board.summary.cols)
                let cellHeight = size.height / Double(board.summary.rows)
                let gap = min(cellWidth, cellHeight) * 0.08
                for row in grid.indices {
                    for column in grid[row].indices {
                        let rect = CGRect(x: Double(column) * cellWidth + gap, y: Double(row) * cellHeight + gap,
                                          width: cellWidth - gap * 2, height: cellHeight - gap * 2)
                        let cell = BoardTables.cell(forCode: grid[row][column], code62: glyph)
                        let color: Color
                        if case .color(let pigment) = cell { color = Color(boardHex: pigment.hex) } else { color = Color(white: 0.13) }
                        context.fill(Path(roundedRect: rect, cornerRadius: gap), with: .color(color))
                        if case .character(let value) = cell {
                            context.draw(Text(String(value)).font(.system(size: cellHeight * 0.64, weight: .bold, design: .monospaced)).foregroundStyle(.white), at: CGPoint(x: rect.midX, y: rect.midY))
                        }
                        var seam = Path()
                        seam.move(to: CGPoint(x: rect.minX, y: rect.midY))
                        seam.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                        context.stroke(seam, with: .color(.black.opacity(0.45)), lineWidth: max(0.5, gap * 0.2))
                    }
                }
            }
            .aspectRatio(Double(board.summary.cols) * 0.7 / Double(board.summary.rows), contentMode: .fit)
            .padding(12)
            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(expected ? "Expected output" : "Server-reported output")
            .accessibilityValue(accessibleText(grid))
        } else {
            ContentUnavailableView {
                Label(grid == nil ? "No reported frame" : "Renderer unavailable", systemImage: "rectangle.slash")
            } description: {
                Text("This draft displays supported split-flap grids up to 4,096 cells. Pixel layers and other character sets need the server’s web preview.")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func accessibleText(_ codes: [[Int]]) -> String {
        codes.map { row in
            row.map { code in
                switch BoardTables.cell(forCode: code, code62: glyph) {
                case .blank: return " "
                case .character(let value): return String(value)
                case .color(let color): return " [\(color.rawValue)] "
                }
            }.joined()
        }.joined(separator: "; ")
    }
}
private extension Color {
    init(boardHex: String) {
        let value = UInt32(boardHex.dropFirst(), radix: 16) ?? 0x1a1a1a
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
