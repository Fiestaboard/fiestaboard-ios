import Foundation

public enum HomeControlOperation: CaseIterable, Sendable { case cancelOverride, selectPage, timedOverride }
public extension CapabilityPolicy {
    /// Scoped I7 operations audited at immutable v11 e8306aca0. This grants no
    /// editor, scalar-setting, evaluation or page-storage write capability.
    static func allowsHomeControl(_ operation: HomeControlOperation, version: String?, hasScopedStatus: Bool) -> Bool {
        hasScopedStatus && version == "11.0.0-alpha.2"
    }
}
public struct HomeControlReceipt: Decodable, Sendable {
    public let boardID: String?
    public let pageID: String?
    public let sent: Bool?
    public let active: Bool?
    public let expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case boardID = "board_id", pageID = "page_id", sent, active, expiresAt = "expires_at"
    }
}
public protocol HomePageSelecting: Sendable {
    func selectHomePage(pageID: String, boardID: String, durationMinutes: Int?) async throws -> HomeControlReceipt
}
extension LiveFiestaBoardService: HomePageSelecting {
    public func selectHomePage(pageID: String, boardID: String, durationMinutes: Int?) async throws -> HomeControlReceipt {
        guard DeploymentURL.validSegment(boardID), DeploymentURL.validSegment(pageID),
              durationMinutes.map({ (1...1440).contains($0) }) ?? true else { throw FiestaBoardError.invalidTarget }
        let request: APIRequest
        if let durationMinutes {
            struct Override: Encodable { let board_id: String; let page_id: String; let duration_minutes: Int; let revert_mode = "schedule" }
            request = APIRequest(.post, path: ["settings", "temporary-override"],
                body: try JSONEncoder().encode(Override(board_id: boardID, page_id: pageID, duration_minutes: durationMinutes)))
        } else {
            struct Selection: Encodable { let page_id: String }
            request = APIRequest(.put, path: ["v1", "boards", boardID, "active-page"],
                body: try JSONEncoder().encode(Selection(page_id: pageID)))
        }
        let result = try await response(request)
        guard result.status == 200, let receipt = try? JSONDecoder().decode(HomeControlReceipt.self, from: result.data),
              receipt.boardID == boardID, receipt.pageID == pageID,
              durationMinutes == nil ? receipt.sent != nil : receipt.active == true else {
            throw FiestaBoardError.unknownMutationOutcome
        }
        return receipt
    }
}
