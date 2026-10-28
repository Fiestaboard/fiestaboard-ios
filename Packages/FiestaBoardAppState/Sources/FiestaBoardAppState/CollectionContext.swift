import Foundation
import FiestaBoardKit

/// Local authorization belongs to one connection and one loaded document.
/// The revision remains the one from that document, even after a list refresh.
public struct CollectionEditingContext: Sendable, Equatable {
    public let deployment: DeploymentURL
    public let generation: UInt64
    public let documentToken: UUID
    public let collectionID: String?
    public let originalRevision: String?
    let writeAllowed: Bool
}

public struct CollectionEditorSnapshot: Sendable {
    public let context: CollectionEditingContext
    public let collection: PageCollection?
    public let pages: [Page]
    public let canSave: Bool
    public let isDemo: Bool
}

struct CollectionIdentity: Hashable {
    let deployment: DeploymentURL
    let id: String
    static func creation(on deployment: DeploymentURL) -> Self { Self(deployment: deployment, id: "__new_collection__") }
}
