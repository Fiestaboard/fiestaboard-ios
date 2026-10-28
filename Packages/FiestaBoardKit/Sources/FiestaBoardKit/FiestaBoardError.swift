import Foundation

/// Deliberately contains no server error text, response bodies, URLs, or credentials.
public enum FiestaBoardError: Error, Sendable, Equatable, LocalizedError {
    case invalidDeployment, insecureDeployment, invalidPath, invalidTarget
    case unauthenticated, conflict, rateLimited(retryAfterSeconds: Int?)
    case partialWrite(failedRegions: [FailedRegion])
    case rejected(status: Int), redirectRefused, invalidResponse, networkUnavailable
    case unknownMutationOutcome, staleSession, writesDisabled
    case stalePageContext, pageConflict, pageWritesDisabled, pageReadbackRequired, previewUnsupported

    case collectionConflict, collectionWritesDisabled, collectionReadbackRequired, collectionInUse, staleCollectionContext

    public var errorDescription: String? {
        switch self {
        case .invalidDeployment: "Enter a valid deployment URL without credentials, query, fragment, or escaped path."
        case .insecureDeployment: "HTTP requires explicit permission and a local network address."
        case .invalidPath: "The API path is invalid."
        case .invalidTarget: "Select a concrete board on this deployment."
        case .unauthenticated: "Sign in to this deployment."
        case .conflict: "The server refused this action because of its current state."
        case .rateLimited: "The server is limiting requests. Wait before trying again."
        case .partialWrite: "Only part of the board accepted the write. Refresh its current output."
        case .rejected(let status): "The server rejected the request (HTTP \(status))."
        case .redirectRefused: "This deployment redirected the request. Check its URL."
        case .invalidResponse: "The server response does not match this draft's contract."
        case .networkUnavailable: "The deployment could not be reached."
        case .unknownMutationOutcome: "The result is unknown. Refresh before sending another action."
        case .staleSession: "The deployment session changed. Refresh to continue."
        case .stalePageContext: "The page context changed. Keep your local work and use the current page snapshot."
        case .pageConflict: "This page changed on the server. Keep your local work and explicitly reload before saving again."
        case .pageWritesDisabled: "Page saving requires page-revision-v1, an original revision, and explicit session opt-in."
        case .pageReadbackRequired: "Read the page again before another save; the previous result may be unknown."
        case .previewUnsupported: "Template preview is unavailable for this server version or request shape."
        case .collectionConflict: "This collection changed on the server. Keep your draft and compare before saving again."
        case .collectionWritesDisabled: "Collection saving requires a supported document, its original revision, and explicit session opt-in. Creating requires the audited 10.1.7 server."
        case .collectionReadbackRequired: "Compare the collection with the server before another write. After an uncertain creation, inspect the list and start a new draft."
        case .collectionInUse: "This collection is still referenced. Remove its references before deleting it."
        case .staleCollectionContext: "The collection context changed. Keep your draft and reopen the current collection."
        case .writesDisabled: "Writes require the exact v10.0.0 candidate and explicit draft opt-in."
        }
    }
}

public struct FailedRegion: Codable, Sendable, Equatable {
    public let row: Int
    public let col: Int
    public let rows: Int
    public let cols: Int
}
