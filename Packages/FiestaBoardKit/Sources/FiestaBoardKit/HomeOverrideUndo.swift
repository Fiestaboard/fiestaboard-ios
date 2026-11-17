import Foundation

/// The explicit capability is absent on older hubs. Receipt authority is never
/// inferred from a version, the presence of an override, or a local snapshot.
public struct HomeOverrideStatus: Decodable, Sendable {
    public let undoSupported: Bool
    public let active: Bool
    public let boardID: String?
    public let pageID: String?
    public let startedAt: String?
    public let expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case undoSupported = "undo_supported", active, boardID = "board_id", pageID = "page_id"
        case startedAt = "started_at", expiresAt = "expires_at"
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        undoSupported = try values.decodeIfPresent(Bool.self, forKey: .undoSupported) ?? false
        active = try values.decode(Bool.self, forKey: .active)
        boardID = try values.decodeIfPresent(String.self, forKey: .boardID)
        pageID = try values.decodeIfPresent(String.self, forKey: .pageID)
        startedAt = try values.decodeIfPresent(String.self, forKey: .startedAt)
        expiresAt = try values.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}
public struct HomeOverrideCancellation: Decodable, Sendable {
    public let undoToken: String?
    public let undoExpiresAt: String?
    enum CodingKeys: String, CodingKey { case revertMode = "revert_mode", undoToken = "undo_token", undoExpiresAt = "undo_expires_at" }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        guard values.contains(.revertMode) else {
            throw DecodingError.keyNotFound(CodingKeys.revertMode,.init(codingPath:decoder.codingPath,debugDescription:"Missing cancellation result"))
        }
        _ = try values.decodeIfPresent(String.self,forKey:.revertMode)
        undoToken = try values.decodeIfPresent(String.self,forKey:.undoToken)
        undoExpiresAt = try values.decodeIfPresent(String.self,forKey:.undoExpiresAt)
    }
}
public protocol HomeOverrideUndoing: Sendable {
    func homeOverrideStatus(boardID: String) async throws -> HomeOverrideStatus
    func cancelHomeOverride(boardID: String, requestingUndo: Bool) async throws -> HomeOverrideCancellation
    func undoHomeOverride(boardID: String, token: String) async throws -> HomeOverrideStatus
}
extension LiveFiestaBoardService: HomeOverrideUndoing {
    public func homeOverrideStatus(boardID: String) async throws -> HomeOverrideStatus {
        guard DeploymentURL.validSegment(boardID) else { throw FiestaBoardError.invalidTarget }
        let status: HomeOverrideStatus = try await fetch(APIRequest(path: ["settings", "temporary-override"],
            queryItems: [URLQueryItem(name: "board_id", value: boardID)], cachePolicy: .noStore))
        guard !status.undoSupported || status.boardID == boardID else { throw FiestaBoardError.invalidResponse }
        return status
    }
    public func cancelHomeOverride(boardID: String, requestingUndo: Bool) async throws -> HomeOverrideCancellation {
        guard DeploymentURL.validSegment(boardID) else { throw FiestaBoardError.invalidTarget }
        var query = [URLQueryItem(name: "board_id", value: boardID)]
        if requestingUndo { query.append(URLQueryItem(name: "undo", value: "true")) }
        let result = try await response(APIRequest(.delete, path: ["settings", "temporary-override"], queryItems: query, cachePolicy: .noStore))
        guard result.status == 200, let receipt = try? JSONDecoder().decode(HomeOverrideCancellation.self, from: result.data),
              (receipt.undoToken == nil) == (receipt.undoExpiresAt == nil),
              receipt.undoToken.map({ !$0.isEmpty && $0.count <= 128 }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        return receipt
    }
    public func undoHomeOverride(boardID: String, token: String) async throws -> HomeOverrideStatus {
        guard DeploymentURL.validSegment(boardID), !token.isEmpty, token.count <= 128 else { throw FiestaBoardError.invalidTarget }
        struct Undo: Encodable { let board_id: String; let undo_token: String }
        let result = try await response(APIRequest(.post, path: ["settings", "temporary-override", "undo"],
            body: try JSONEncoder().encode(Undo(board_id: boardID, undo_token: token)), cachePolicy: .noStore))
        guard result.status == 200, let restored = try? JSONDecoder().decode(HomeOverrideStatus.self, from: result.data),
              restored.active, restored.boardID == boardID else { throw FiestaBoardError.unknownMutationOutcome }
        return restored
    }
}
