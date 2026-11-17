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
public protocol HomePageHolding: Sendable {
    func holdHomePage(pageID: String, boardID: String, durationMinutes: Int?) async throws -> HomeControlReceipt
}
extension LiveFiestaBoardService: HomePageSelecting, HomePageHolding {
    public func selectHomePage(pageID: String, boardID: String, durationMinutes: Int?) async throws -> HomeControlReceipt {
        if let durationMinutes { return try await holdHomePage(pageID: pageID, boardID: boardID, durationMinutes: durationMinutes) }
        guard DeploymentURL.validSegment(boardID), DeploymentURL.validSegment(pageID) else { throw FiestaBoardError.invalidTarget }
        struct Selection: Encodable { let page_id: String }
        let request = APIRequest(.put, path: ["v1", "boards", boardID, "active-page"],
            body: try JSONEncoder().encode(Selection(page_id: pageID)))
        return try await homeReceipt(request, boardID: boardID, pageID: pageID, temporary: false)
    }
    public func holdHomePage(pageID: String, boardID: String, durationMinutes: Int?) async throws -> HomeControlReceipt {
        guard DeploymentURL.validSegment(boardID), DeploymentURL.validSegment(pageID),
              durationMinutes.map({ (1...480).contains($0) }) ?? true else { throw FiestaBoardError.invalidTarget }
        struct Override: Encodable {
            let board_id: String; let page_id: String; let duration_minutes: Int?; let revert_mode = "schedule"
        }
        let request = APIRequest(.post, path: ["settings", "temporary-override"],
            body: try JSONEncoder().encode(Override(board_id: boardID, page_id: pageID, duration_minutes: durationMinutes)))
        let receipt = try await homeReceipt(request, boardID: boardID, pageID: pageID, temporary: true)
        guard durationMinutes == nil || receipt.expiresAt != nil else { throw FiestaBoardError.unknownMutationOutcome }
        return receipt
    }
    private func homeReceipt(_ request: APIRequest, boardID: String, pageID: String, temporary: Bool) async throws -> HomeControlReceipt {
        let result = try await response(request)
        guard result.status == 200, let receipt = try? JSONDecoder().decode(HomeControlReceipt.self, from: result.data),
              receipt.boardID == boardID, receipt.pageID == pageID,
              temporary ? receipt.active == true : receipt.sent != nil else {
            throw FiestaBoardError.unknownMutationOutcome
        }
        return receipt
    }
}
