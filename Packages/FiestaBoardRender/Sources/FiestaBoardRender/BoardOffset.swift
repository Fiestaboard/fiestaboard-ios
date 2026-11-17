/// Pure presentation offset, ported from tvOS f1fc67d SignageSettings.
public struct BoardOffset: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = BoardOffset(x: 0, y: 0)
}
