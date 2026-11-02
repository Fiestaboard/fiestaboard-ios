import Foundation
import FiestaBoardKit

/// Injected by the app around one immutable deployment/session/page context. Documents themselves
/// have no network dependency. Every closure is MainActor isolated, including its context holder.
public struct EditorRemoteActions {
    public let isSimulated: Bool
    public let disabledReason: @MainActor () -> String?
    public let save: @MainActor (PageSavePatch) async throws -> EditorSaveResult
    public let fetch: (@MainActor () async throws -> Data)?
    public let validate: (@MainActor (Data, BoardTarget) async throws -> TemplateValidationResult)?
    public let previewFlexible: (@MainActor (Data, BoardTarget) async throws -> FlexiblePreviewResult)?
    public let preview: (@MainActor (Data, BoardTarget) async throws -> TemplatePreviewResult)?
    public init(isSimulated: Bool = false, disabledReason: @escaping @MainActor () -> String?,
                save: @escaping @MainActor (PageSavePatch) async throws -> EditorSaveResult,
                fetch: (@MainActor () async throws -> Data)? = nil,
                validate: (@MainActor (Data, BoardTarget) async throws -> TemplateValidationResult)? = nil,
                preview: (@MainActor (Data, BoardTarget) async throws -> TemplatePreviewResult)? = nil,
                previewFlexible: (@MainActor (Data, BoardTarget) async throws -> FlexiblePreviewResult)? = nil) {
        self.isSimulated = isSimulated
        self.disabledReason = disabledReason; self.save = save; self.fetch = fetch
        self.validate = validate; self.preview = preview; self.previewFlexible = previewFlexible
    }
}

public struct EditorBoardChoice: Identifiable, Sendable {
    public var id: String { target.boardID }
    public let name: String
    public let target: BoardTarget
    /// The display's grid, when known: the stage picks a display the page fits (P1).
    public let rows: Int?
    public let cols: Int?
    /// What the display is (`/v1/boards`), so the editor can tell a pixel matrix (PLAN B24).
    public let deviceType: String?
    public let deviceModel: String?
    public let charset: String?
    public init(name: String, target: BoardTarget, rows: Int? = nil, cols: Int? = nil,
                deviceType: String? = nil, deviceModel: String? = nil, charset: String? = nil) {
        self.name = name; self.target = target; self.rows = rows; self.cols = cols
        self.deviceType = deviceType; self.deviceModel = deviceModel; self.charset = charset
    }
    /// Whether a page of `rows` × `cols` shows on this display as authored; nil when unknown.
    public func fits(rows: Int, cols: Int) -> Bool? {
        guard let ownRows = self.rows, let ownCols = self.cols else { return nil }
        return ownRows == rows && ownCols == cols
    }
    /// The display the editor opens on: the one remembered for this page, else the first that
    /// fits the page, else the first one (whose header then says it doesn't fit).
    public static func initialChoice(_ boards: [EditorBoardChoice], remembered: String?, rows: Int, cols: Int) -> String? {
        if let remembered, boards.contains(where: { $0.id == remembered }) { return remembered }
        return boards.first(where: { $0.fits(rows: rows, cols: cols) == true })?.id ?? boards.first?.id
    }
}
public enum EditorRemoteStatus: Equatable, Sendable {
    case idle, saving, conflict, unknownOutcome, reading, comparison
}

public struct EditorSaveResult: Sendable {
    public let data: Data
    public let incompatibleReferenceCount: Int
    public init(data: Data, incompatibleReferenceCount: Int = 0) {
        self.data = data; self.incompatibleReferenceCount = incompatibleReferenceCount
    }
}
