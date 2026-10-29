import Foundation

public enum DefaultPageChange: Sendable, Equatable { case omit, set(String), clear }
/// Only explicit fields are encoded. Clearing the default differs from leaving it untouched.
public struct BoardPatch: Encodable, Sendable, Equatable {
    public let paused: Bool?
    public let scheduleEnabled: Bool?
    public let autoRestore: Bool?
    public let defaultPage: DefaultPageChange
    public init(paused: Bool? = nil, scheduleEnabled: Bool? = nil, autoRestore: Bool? = nil,
                defaultPage: DefaultPageChange = .omit) {
        self.paused = paused; self.scheduleEnabled = scheduleEnabled
        self.autoRestore = autoRestore; self.defaultPage = defaultPage
    }
    public var isEmpty: Bool { paused == nil && scheduleEnabled == nil && autoRestore == nil && defaultPage == .omit }
    public func validate() throws {
        guard !isEmpty else { throw FiestaBoardError.invalidTarget }
        if case .set(let id) = defaultPage, !DeploymentURL.validSegment(id) { throw FiestaBoardError.invalidPath }
    }
    enum CodingKeys: String, CodingKey {
        case paused, scheduleEnabled = "schedule_enabled", autoRestore = "auto_restore", defaultPage = "default_page_id"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(paused, forKey: .paused)
        try c.encodeIfPresent(scheduleEnabled, forKey: .scheduleEnabled)
        try c.encodeIfPresent(autoRestore, forKey: .autoRestore)
        switch defaultPage {
        case .omit: break
        case .set(let id): try c.encode(id, forKey: .defaultPage)
        case .clear: try c.encodeNil(forKey: .defaultPage)
        }
    }
}
/// The server returned a configuration snapshot. This never acknowledges a hardware send.
public struct BoardConfigurationReceipt: Sendable {
    public let board: BoardDetail
    public init(board: BoardDetail) { self.board = board }
}
/// Restore retains the pinned selection. Accepted writes do not establish physical output.
public struct BoardRestoreReceipt: Decodable, Sendable {
    public let boardID: String
    public let pageID: String?
    public let sent: Bool
    public let reason: String?
    public let deviceObserved: Bool
    enum CodingKeys: String, CodingKey {
        case boardID = "board_id", pageID = "page_id", sent, reason, deviceObserved = "device_observed"
    }
}

public struct BoardDefaultSnapshot: Decodable, Sendable, Equatable {
    public let revision: String
    public let editProtocol: String
    public let defaultPageID: String?
    enum CodingKeys: String, CodingKey { case revision, editProtocol = "edit_protocol", defaultPageID = "default_page_id" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.defaultPageID) else { throw FiestaBoardError.invalidResponse }
        revision = try c.decode(String.self, forKey: .revision)
        editProtocol = try c.decode(String.self, forKey: .editProtocol)
        defaultPageID = try c.decodeIfPresent(String.self, forKey: .defaultPageID)
    }
    func validate() throws {
        guard !revision.isEmpty, revision.count <= 256, editProtocol == "schedule-default-revision-v1",
              defaultPageID.map(DeploymentURL.validSegment) ?? true else { throw FiestaBoardError.invalidResponse }
    }
}
/// Immutable scope and revision from one original read; only the issuing service can consume it.
public struct BoardDefaultContext: Sendable, Equatable {
    public let target: BoardTarget
    public let snapshot: BoardDefaultSnapshot
    let generation: UInt64
    let token: UUID
}
public extension FiestaBoardService {
    func defaultPageWriteCapability() async -> DefaultPageWriteCapability { .unavailable }
    func readDefaultPage(on target: BoardTarget) async throws -> BoardDefaultContext { throw FiestaBoardError.writesDisabled }
    func updateDefaultPage(_ change: DefaultPageChange, context: BoardDefaultContext) async throws -> BoardDefaultSnapshot { throw FiestaBoardError.writesDisabled }
}

/// Advertised explicitly; a failed conditional read never grants legacy access.
public enum DefaultPageWriteCapability: Sendable, Equatable {
    case unavailable, conditional, legacyUnconditioned, simulated
}
