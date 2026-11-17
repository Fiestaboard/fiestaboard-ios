import Foundation

/// The "what's happening" reads (PLAN §2.3). All are GETs (never mutations,
/// never retried by the caller); internal routes need the session cookie.
public protocol BoardStatusReading: Sendable {
    var deployment: DeploymentURL { get }
    func boardSettings() async throws -> [StoredBoardEntry]
    func serviceStatus() async throws -> ServiceStatusReport
    func currentMessage(boardID: String) async throws -> CurrentBoardMessage
    func activeSchedulePage(boardID: String) async throws -> ActivePageStatus
    func activePage(boardID: String) async throws -> ActivePageStatus
    func silenceStatus(boardID: String) async throws -> SilenceStatus
    func displaySettings() async throws -> BoardDisplaySettings
    /// `/v1/collections` names keyed by id (read loosely: only id + name).
    func collectionNames() async throws -> [String: String]
}

private struct RawJSON: Decodable, Sendable {
    let data: Data
    init(from decoder: any Decoder) throws {
        // Re-encode through a generic container to keep the raw object.
        let value = try decoder.singleValueContainer().decode(AnyJSON.self)
        data = try JSONSerialization.data(withJSONObject: value.object)
    }
}
private struct AnyJSON: Decodable {
    let object: Any
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { object = NSNull() }
        else if let v = try? c.decode(Bool.self) { object = v }
        else if let v = try? c.decode(Int.self) { object = v }
        else if let v = try? c.decode(Double.self) { object = v }
        else if let v = try? c.decode(String.self) { object = v }
        else if let v = try? c.decode([AnyJSON].self) { object = v.map(\.object) }
        else { object = try c.decode([String: AnyJSON].self).mapValues(\.object) }
    }
}

extension LiveFiestaBoardService: BoardStatusReading {
    private func boardQuery(_ id: String) throws -> [URLQueryItem] {
        guard DeploymentURL.validSegment(id) else { throw FiestaBoardError.invalidTarget }
        return [URLQueryItem(name: "board_id", value: id)]
    }
    public func boardSettings() async throws -> [StoredBoardEntry] {
        let raw: RawJSON = try await fetch(APIRequest(path: ["settings", "board"], cachePolicy: .noStore))
        return try StoredBoardEntry.decodeList(raw.data)
    }
    public func serviceStatus() async throws -> ServiceStatusReport {
        try await fetch(APIRequest(path: ["v1", "status"], cachePolicy: .noStore))
    }
    public func currentMessage(boardID: String) async throws -> CurrentBoardMessage {
        try await fetch(APIRequest(path: ["board", "current-message"], queryItems: boardQuery(boardID), cachePolicy: .noStore))
    }
    public func activeSchedulePage(boardID: String) async throws -> ActivePageStatus {
        try await fetch(APIRequest(path: ["schedules", "active", "page"], queryItems: boardQuery(boardID), cachePolicy: .noStore))
    }
    public func activePage(boardID: String) async throws -> ActivePageStatus {
        try await fetch(APIRequest(path: ["settings", "active-page"], queryItems: boardQuery(boardID), cachePolicy: .noStore))
    }
    public func silenceStatus(boardID: String) async throws -> SilenceStatus {
        try await fetch(APIRequest(path: ["silence-status"], queryItems: boardQuery(boardID), cachePolicy: .noStore))
    }
    public func displaySettings() async throws -> BoardDisplaySettings {
        try await fetch(APIRequest(path: ["settings", "display"], cachePolicy: .noStore))
    }
    public func collectionNames() async throws -> [String: String] {
        struct Item: Decodable { let id: String; let name: String }
        struct List: Decodable { let collections: [Item] }
        let list: List = try await fetch(APIRequest(path: ["v1", "collections"], cachePolicy: .noStore))
        return Dictionary(list.collections.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Forget a board's remembered external frame (`DELETE /board/external-frame`,
/// web "Dismiss" on the kept face). Idempotent on the server (204 either way).
public protocol ExternalFrameDismissing: Sendable {
    func dismissExternalFrame(boardID: String) async throws
}

extension LiveFiestaBoardService: ExternalFrameDismissing {
    public func dismissExternalFrame(boardID: String) async throws {
        guard DeploymentURL.validSegment(boardID) else { throw FiestaBoardError.invalidTarget }
        let result = try await response(APIRequest(.delete, path: ["board", "external-frame"],
                                                   queryItems: [URLQueryItem(name: "board_id", value: boardID)]))
        guard (200..<300).contains(result.status) else { throw FiestaBoardError.unknownMutationOutcome }
    }
}

/// Cancel the active temporary override (`DELETE /settings/temporary-override`, the web's ✕ on
/// the "Override: Nm remaining" badge, `clearTemporaryOverride`). Every request explicitly names the display; the
/// server refreshes the board itself. Explicit only, never replayed.
public protocol TemporaryOverrideClearing: Sendable {
    func clearTemporaryOverride(boardID: String) async throws
}

extension LiveFiestaBoardService: TemporaryOverrideClearing {
    public func clearTemporaryOverride(boardID: String) async throws {
        guard DeploymentURL.validSegment(boardID) else { throw FiestaBoardError.invalidTarget }
        let result = try await response(APIRequest(.delete, path: ["settings", "temporary-override"],
            queryItems: [URLQueryItem(name: "board_id", value: boardID)]))
        guard (200..<300).contains(result.status) else { throw FiestaBoardError.unknownMutationOutcome }
    }
}
