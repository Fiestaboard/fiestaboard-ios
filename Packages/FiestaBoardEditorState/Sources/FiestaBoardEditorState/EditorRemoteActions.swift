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
    public let preview: (@MainActor (Data, BoardTarget) async throws -> TemplatePreviewResult)?
    public init(isSimulated: Bool = false, disabledReason: @escaping @MainActor () -> String?,
                save: @escaping @MainActor (PageSavePatch) async throws -> EditorSaveResult,
                fetch: (@MainActor () async throws -> Data)? = nil,
                validate: (@MainActor (Data, BoardTarget) async throws -> TemplateValidationResult)? = nil,
                preview: (@MainActor (Data, BoardTarget) async throws -> TemplatePreviewResult)? = nil) {
        self.isSimulated = isSimulated
        self.disabledReason = disabledReason; self.save = save; self.fetch = fetch
        self.validate = validate; self.preview = preview
    }
}

public struct EditorBoardChoice: Identifiable, Sendable {
    public var id: String { target.boardID }
    public let name: String
    public let target: BoardTarget
    public init(name: String, target: BoardTarget) { self.name = name; self.target = target }
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
