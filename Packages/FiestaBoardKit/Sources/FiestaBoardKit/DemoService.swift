import Foundation

public enum DemoSimulation: String, CaseIterable, Codable, Sendable { case accepted, held, partial, rejected, unknown }

/// Every action stays in memory. The demo never creates a URLSession or contacts hardware.
public actor DemoFiestaBoardService: FiestaBoardService {
    public nonisolated let deployment: DeploymentURL
    public nonisolated let isDemo = true
    private let simulation: DemoTransport
    private let service: LiveFiestaBoardService

    public init() throws {
        deployment = try DeploymentURL("https://demo.fiestaboard.invalid")
        simulation = try DemoTransport()
        service = LiveFiestaBoardService(deployment: deployment, transport: simulation)
    }
    public func setSimulation(_ mode: DemoSimulation) async { await simulation.setMode(mode) }
    public func authStatus() async throws -> AuthStatus { try await service.authStatus() }
    public func login(username: String, password: String) async throws -> AuthStatus { try await service.authStatus() }
    public func logout() async throws { try await service.logout() }
    public func connect(allowCandidateWrites: Bool = false) async throws -> ConnectionStatus {
        let status = try await service.connect(allowCandidateWrites: true)
        return ConnectionStatus(version: status.version, access: .simulated, isDemo: true, sessionPersistence: "Simulated; memory only")
    }
    public func boards() async throws -> [BoardSummary] { try await service.boards() }
    public func board(_ target: BoardTarget) async throws -> BoardDetail { try await service.board(target) }
    public func pages() async throws -> [Page] { try await service.pages() }
    public func pageDocumentData(id: String) async throws -> Data { try await service.pageDocumentData(id: id) }
    public func page(id: String) async throws -> Page { try await service.page(id: id) }
    public func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { try await service.updateBoard(patch, on: target) }
    public func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { try await service.restoreBoard(target) }
    public func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { try await service.sendText(text, to: target) }
    public func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await service.selectPage(id: id, on: target) }
}

private actor DemoTransport: APITransport {
    private var data: [String: Data] = [:]
    private var mode = DemoSimulation.accepted

    init() throws {
        for name in ["boards", "board", "board-led", "pages", "page", "page-weather"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "DemoFixtures") else {
                throw FiestaBoardError.invalidResponse
            }
            data[name] = try Data(contentsOf: url)
        }
        for name in ["board", "board-led"] {
            try JSONDecoder().decode(BoardDetail.self, from: data[name]!).validate()
        }
    }
    func setMode(_ mode: DemoSimulation) { self.mode = mode }
    func resetSession() {}

    func send(_ request: APIRequest) async throws -> APIResponse {
        let path = request.path
        if path == ["version"] {
            return reply(#"{"package_version":"10.0.0","build_version":"simulated-draft","running_version":"10.0.0","is_dev":false}"#)
        }
        if path == ["auth", "status"] {
            return reply(#"{"enabled":false,"setup_required":false,"authenticated":false,"username":null,"mode":"disabled","first_run":false}"#)
        }
        if path == ["auth", "logout"] { return reply(#"{"status":"ok"}"#) }
        if path == ["v1", "boards"] { return APIResponse(status: 200, data: data["boards"]!) }
        if path == ["v1", "pages"] { return APIResponse(status: 200, data: data["pages"]!) }
        if path.count == 3 && path.prefix(2) == ["v1", "pages"] {
            let name = path[2] == "page-selected" ? "page" : path[2]
            guard let fixture = data[name] else { throw FiestaBoardError.rejected(status: 404) }
            return APIResponse(status: 200, data: fixture)
        }
        guard path.count >= 3, path.prefix(2) == ["v1", "boards"], ["board-2", "board-led"].contains(path[2]) else {
            throw FiestaBoardError.rejected(status: 404)
        }
        let key = path[2] == "board-2" ? "board" : "board-led"
        if path.count == 3 && request.method == .patch {
            if mode == .rejected { throw FiestaBoardError.conflict }
            var board = try JSONSerialization.jsonObject(with: data[key]!) as! [String: Any]
            let body = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
            if let page = body["default_page_id"] as? String, !["page-selected", "page-weather"].contains(page) { throw FiestaBoardError.rejected(status: 404) }
            for (field, value) in body { board[field] = value }
            if board["schedule_enabled"] as? Bool == true {
                board["source"] = "schedule"
                board["resolved_page_id"] = board["scheduled_page_id"] ?? board["default_page_id"] ?? NSNull()
            } else {
                board["source"] = board["active_page_id"] is String ? "manual" : "none"
                board["resolved_page_id"] = board["active_page_id"] ?? NSNull()
            }
            data[key] = try JSONSerialization.data(withJSONObject: board)
            var list = try JSONSerialization.jsonObject(with: data["boards"]!) as! [String: Any]
            var summaries = list["boards"] as! [[String: Any]]
            if let index = summaries.firstIndex(where: { $0["id"] as? String == path[2] }) {
                for field in ["paused", "schedule_enabled", "auto_restore"] { summaries[index][field] = board[field] }
            }
            list["boards"] = summaries; data["boards"] = try JSONSerialization.data(withJSONObject: list)
            if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
            return APIResponse(status: 200, data: data[key]!)
        }
        guard path.count == 4 else { return APIResponse(status: 200, data: data[key]!) }
        var board = try JSONSerialization.jsonObject(with: data[key]!) as! [String: Any]
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data("{}".utf8)) as! [String: Any]
        if mode == .rejected { throw FiestaBoardError.conflict }
        if path[3] == "restore" {
            if board["paused"] as? Bool == true || mode == .held { throw FiestaBoardError.conflict }
            if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: [
                "board_id": path[2], "page_id": board["active_page_id"] ?? NSNull(),
                "sent": true, "reason": NSNull(), "device_observed": false]))
        }
        if board["paused"] as? Bool == true { throw FiestaBoardError.conflict }
        let selectedPage = body["page_id"] as? String
        var text = body["text"] as? String ?? "SUN DAY"
        if let selectedPage {
            guard ["page-selected", "page-weather"].contains(selectedPage) else { throw FiestaBoardError.rejected(status: 404) }
            board["active_page_id"] = selectedPage
            if selectedPage == "page-selected" { text = "WELCOME" }
        }
        // Deliberately simple simulated text layout, not a promise of server word-wrapping parity.
        let rows = board["rows"] as! Int, cols = board["cols"] as! Int
        var codes = text.uppercased().unicodeScalars.map { (65...90).contains($0.value) ? Int($0.value - 64) : 0 }
        codes = Array((codes + [Int](repeating: 0, count: rows * cols)).prefix(rows * cols))
        let grid = (0..<rows).map { Array(codes[($0 * cols)..<(($0 + 1) * cols)]) }
        let previousGrid = board["characters"] as? [[Int]]
        board["expected_characters"] = grid
        if mode != .held {
            board["characters"] = grid
            board["text"] = text
            if let selectedPage { board["resolved_page_id"] = selectedPage }
        }
        if mode == .partial {
            var partialGrid = grid
            partialGrid[rows - 1] = previousGrid?[rows - 1] ?? [Int](repeating: 0, count: cols)
            board["characters"] = partialGrid
        }
        data[key] = try JSONSerialization.data(withJSONObject: board)
        if mode == .unknown { throw FiestaBoardError.unknownMutationOutcome }
        if mode == .partial {
            let region = try JSONDecoder().decode(FailedRegion.self, from: Data("{\"row\":\(rows - 1),\"col\":0,\"rows\":1,\"cols\":\(cols)}".utf8))
            throw FiestaBoardError.partialWrite(failedRegions: [region])
        }
        let result: [String: Any]
        if let selectedPage {
            result = ["board_id":path[2], "page_id":selectedPage, "sent":mode == .accepted,
                      "silenced":mode == .held, "error":NSNull(), "warnings":[]]
        } else {
            result = ["board_id":path[2], "sent":mode == .accepted, "characters":grid, "text":text,
                      "held":mode == .held, "silenced":mode == .held]
        }
        return APIResponse(status: selectedPage == nil && mode == .held ? 202 : 200,
                           data: try JSONSerialization.data(withJSONObject: result))
    }
    private func reply(_ json: String) -> APIResponse { APIResponse(status: 200, data: Data(json.utf8)) }
}
