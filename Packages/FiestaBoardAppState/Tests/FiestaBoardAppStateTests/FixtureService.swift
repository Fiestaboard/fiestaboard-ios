@testable import FiestaBoardKit
import Foundation

public enum FixtureSimulation: String, CaseIterable, Codable, Sendable { case accepted, held, partial, rejected, unknown }

/// Every action stays in memory. The demo never creates a URLSession or contacts hardware.
public actor FixtureFiestaBoardService: FiestaBoardService {
    public nonisolated let deployment: DeploymentURL
    public nonisolated let isDemo = true
    private let simulation: FixtureTransport
    private let service: LiveFiestaBoardService

    public init() throws {
        deployment = try DeploymentURL("https://demo.fiestaboard.invalid")
        simulation = try FixtureTransport()
        service = LiveFiestaBoardService(demoDeployment: deployment, transport: simulation)
    }
    public func bootstrap() async throws -> BootstrapSnapshot {
        try BootstrapSnapshot(deployment: deployment,
            health: ServerHealth(status: "ok", serviceRunning: true, version: "10.0.0"),
            identity: ServerIdentity(product: "FiestaBoard", version: "10.0.0", installationID: "demo", name: "Demo"),
            auth: AuthStatus(enabled: false, setupRequired: false, authenticated: false, mode: "disabled", firstRun: false))
    }
    public func login(username: String, password: String, rememberMe: Bool) async throws -> AuthStatus { try await authStatus() }
    public func setSimulation(_ mode: FixtureSimulation) async { await simulation.setMode(mode) }
    public func authStatus() async throws -> AuthStatus { try await service.authStatus() }
    public func login(username: String, password: String) async throws -> AuthStatus { try await service.authStatus() }
    public func logout() async throws { try await service.logout() }
    public func connect(allowCandidateWrites: Bool = false) async throws -> ConnectionStatus {
        let status = try await service.connect(allowCandidateWrites: true)
        return ConnectionStatus(version: status.version, access: .simulated, isDemo: true, sessionPersistence: "Simulated; memory only")
    }
    public func boards() async throws -> [BoardSummary] { try await service.boards() }
    public func board(_ target: BoardTarget) async throws -> BoardDetail { try await service.board(target) }
    public func collectionAccess() async -> CollectionWriteAccess {
        let access = await service.collectionAccess()
        return .init(writesOptedIn: access.writesOptedIn, canCreate: access.canCreate, isSimulated: true)
    }
    public func collections() async throws -> [PageCollection] { try await service.collections() }
    public func scopedCollectionDocument(id: String?) async throws -> ScopedCollectionDocument { try await service.scopedCollectionDocument(id: id) }
    public func collection(id: String) async throws -> PageCollection { try await service.collection(id: id) }
    public func acknowledgeCollectionCreationReview() async throws { try await service.acknowledgeCollectionCreationReview() }
    public func createCollection(_ input: CollectionInput) async throws -> PageCollection { try await service.createCollection(input) }
    public func updateCollection(id: String, input: CollectionInput, expectedRevision: String) async throws -> PageCollection {
        try await service.updateCollection(id: id, input: input, expectedRevision: expectedRevision)
    }
    public func deleteCollection(id: String, expectedRevision: String) async throws { try await service.deleteCollection(id: id, expectedRevision: expectedRevision) }
    public func pageManagementCapability() async -> PageManagementCapability { await service.pageManagementCapability() }
    public func preparePageCreation(_ input: PageCreationInput) async throws -> PageCreationContext { try await service.preparePageCreation(input) }
    public func createPage(context: PageCreationContext) async throws -> PageCreationReceipt { try await service.createPage(context: context) }
    public func readPageForDeletion(id: String) async throws -> PageDeletionContext { try await service.readPageForDeletion(id: id) }
    public func deletePage(context: PageDeletionContext) async throws -> PageDeletionReceipt { try await service.deletePage(context: context) }
    public func disconnect() async { await service.disconnect() }
    public func schedules(on target: BoardTarget) async throws -> ScheduleList { try await service.schedules(on: target) }
    public func pages() async throws -> [Page] { try await service.pages() }
    public func scopedPageDocument(id: String) async throws -> ScopedPageDocument { try await service.scopedPageDocument(id: id) }
    public func pageDocumentData(id: String) async throws -> Data { try await service.pageDocumentData(id: id) }
    public func page(id: String) async throws -> Page { try await service.page(id: id) }
    public func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { try await service.savePage(id: id, patch: patch) }
    public func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult {
        let result = try await service.validatePage(requestData: requestData, target: target)
        return try TemplateValidationResult(rawData: result.rawData, isSimulated: true)
    }
    public func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult {
        let result = try await service.previewPage(requestData: requestData, target: target)
        return try TemplatePreviewResult(rawData: result.rawData, isSimulated: true)
    }
    public func defaultPageWriteCapability() async -> DefaultPageWriteCapability { .simulated }
    public func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { try await service.updateBoard(patch, on: target) }
    public func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { try await service.restoreBoard(target) }
    public func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { try await service.sendText(text, to: target) }
    public func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await service.selectPage(id: id, on: target) }
}

private actor FixtureTransport: APITransport {
    private var data: [String: Data] = [:]
    private var pageKeys: Set<String> = ["page", "page-weather"]
    private var mode = FixtureSimulation.accepted
    private var collections: [String: PageCollection] = [:]

    init() throws {
        for name in ["boards", "board", "board-led", "pages", "page", "page-weather"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "ServiceFixtures") else {
                throw FiestaBoardError.invalidResponse
            }
            data[name] = try Data(contentsOf: url)
        }
        for name in ["page", "page-weather"] {
            var page = try JSONSerialization.jsonObject(with: data[name]!) as! [String: Any]
            page["document_protocol"] = "page-document-v1"
            page["revision"] = "demo-original-" + name; page["edit_protocol"] = "page-revision-v1"
            data[name] = try JSONSerialization.data(withJSONObject: page)
        }
        for name in ["board", "board-led"] {
            try JSONDecoder().decode(BoardDetail.self, from: data[name]!).validate()
        }
    }
    func setMode(_ mode: FixtureSimulation) { self.mode = mode }
    func resetSession() {}

    func send(_ request: APIRequest) async throws -> APIResponse {
        let path = request.path
        if path == ["version"] {
            return reply(#"{"package_version":"10.0.0","build_version":"simulated-draft","running_version":"10.0.0","is_dev":false}"#)
        }
        if path == ["auth", "status"] {
            return reply(#"{"enabled":false,"setup_required":false,"authenticated":false,"username":null,"mode":"disabled","first_run":false}"#)
        }
        if path == ["auth", "device", "session"] { return reply(#"{"status":"ok"}"#) }
        if path.starts(with: ["v1", "collections"]) { return try collectionResponse(request) }
        if path == ["v1", "schedules"], request.method == .get {
            guard let boardID = request.queryItems.first(where: { $0.name == "board_id" })?.value,
                  ["board-2", "board-led"].contains(boardID) else { throw FiestaBoardError.invalidTarget }
            let entry: [String: Any] = ["id": "demo-morning", "revision": "demo-schedule-r1",
                "edit_protocol": "schedule-revision-v1", "board_id": boardID, "page_id": "page-weather",
                "start_time": "08:00", "end_time": "10:00", "day_pattern": "weekdays", "enabled": true,
                "recurrence_type": "weekly", "start_type": "fixed", "end_type": "fixed",
                "resolved_start_time": "08:00", "resolved_end_time": "10:00"]
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: [
                "schedules": [entry], "total": 1, "default_page_id": "page-selected", "enabled": true]))
        }
        if path == ["v1", "boards"] { return APIResponse(status: 200, data: data["boards"]!) }
        if path == ["templates", "validate"] { return reply(#"{"valid":true,"errors":[]}"#) }
        if path == ["templates", "render"] {
            let body = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
            let template = (body["template"] as? [String]) ?? (body["template"] as? String)?.components(separatedBy: "\n") ?? []
            // A literal simulation, not server evaluation of plugins, formulas or canvas drawing.
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: [
                "rendered": template.joined(separator: "\n"), "lines": template, "line_count": template.count,
                "charset": NSNull(), "charset_issues": NSNull(), "simulation": "Literal template only; dynamic expressions and canvases are not evaluated."
            ]))
        }
        if path == ["v1", "pages"] {
            if request.method == .post {
                if mode == .rejected { throw FiestaBoardError.rejected(status: 422) }
                var page = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
                let id = "demo-page-" + UUID().uuidString
                page["id"] = id; page["revision"] = "demo-" + UUID().uuidString
                page["edit_protocol"] = "page-revision-v1"; page["document_protocol"] = "page-document-v1"
                let bytes = try JSONSerialization.data(withJSONObject: page)
                data[id] = bytes; pageKeys.insert(id)
                if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
                return APIResponse(status: 201, data: bytes)
            }
            let orderedKeys = ["page", "page-weather"].filter { pageKeys.contains($0) } + pageKeys.subtracting(["page", "page-weather"]).sorted()
            let pages = try orderedKeys.map { try JSONSerialization.jsonObject(with: data[$0]!) }
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["pages": pages, "total": pages.count]))
        }
        if path.count == 3 && path.prefix(2) == ["v1", "pages"] {
            let name = path[2] == "page-selected" ? "page" : path[2]
            guard let fixture = data[name] else { throw FiestaBoardError.rejected(status: 404) }
            if request.method == .delete {
                if mode == .rejected { throw FiestaBoardError.pageInUse }
                let page = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
                guard request.queryItems.first(where: { $0.name == "expected_revision" })?.value == page["revision"] as? String else { throw FiestaBoardError.pageConflict }
                // Explicit demo refusal for configured defaults/collections; no hardware behavior is simulated.
                guard !collections.values.contains(where: { $0.pageIDs.contains(path[2]) }) else { throw FiestaBoardError.pageInUse }
                for key in ["board", "board-led"] {
                    let board = try JSONSerialization.jsonObject(with: data[key]!) as! [String: Any]
                    if board["default_page_id"] as? String == path[2] || board["scheduled_page_id"] as? String == path[2] { throw FiestaBoardError.pageInUse }
                }
                pageKeys.remove(name); data.removeValue(forKey: name)
                var replacementID: String?
                var activeID: String?
                var compatible: [[String: Any]] = []
                for key in pageKeys.sorted() {
                    let other = try JSONSerialization.jsonObject(with: data[key]!) as! [String: Any]
                    if other["device_type"] as? String == page["device_type"] as? String,
                       other["grid_rows"] as? Int == page["grid_rows"] as? Int,
                       other["grid_cols"] as? Int == page["grid_cols"] as? Int { compatible.append(other) }
                }
                var hasActiveReference = false
                for key in ["board", "board-led"] {
                    let board = try JSONSerialization.jsonObject(with: data[key]!) as! [String: Any]
                    if board["active_page_id"] as? String == path[2] { hasActiveReference = true }
                }
                if pageKeys.isEmpty || (hasActiveReference && compatible.isEmpty) {
                    var welcome = page; let id = "demo-welcome-" + UUID().uuidString
                    welcome["id"] = id; welcome["name"] = "Welcome"; welcome["template"] = ["WELCOME"]
                    welcome["revision"] = "demo-" + UUID().uuidString
                    data[id] = try JSONSerialization.data(withJSONObject: welcome); pageKeys.insert(id); replacementID = id
                }
                for key in ["board", "board-led"] {
                    var board = try JSONSerialization.jsonObject(with: data[key]!) as! [String: Any]
                    if board["active_page_id"] as? String == path[2] {
                        let id = replacementID ?? compatible.first!["id"] as! String
                        board["active_page_id"] = id; board["resolved_page_id"] = id; activeID = id
                        data[key] = try JSONSerialization.data(withJSONObject: board)
                    }
                }
                if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
                return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["id": path[2], "message": "Simulated deletion", "default_page_created": replacementID != nil, "new_page_id": replacementID as Any? ?? NSNull(), "active_page_updated": activeID != nil, "new_active_page_id": activeID as Any? ?? NSNull()]))
            }
            if request.method == .put {
                var page = try RawJSONObject.members(fixture)
                let body = try RawJSONObject.members(request.body!)
                guard mode != .rejected,
                      let expected = body["expected_revision"], let revision = page["revision"],
                      try JSONDecoder().decode(String.self, from: expected) == JSONDecoder().decode(String.self, from: revision) else { throw FiestaBoardError.pageConflict }
                for field in ["name", "template", "line_metadata"] { if let value = body[field] { page[field] = value } }
                page["revision"] = try JSONEncoder().encode("demo-" + UUID().uuidString)
                var updated = Data([123])
                for (index, key) in page.keys.sorted().enumerated() {
                    if index > 0 { updated.append(44) }
                    updated.append(try JSONEncoder().encode(key)); updated.append(58); updated.append(page[key]!)
                }
                updated.append(125)
                data[name] = updated
                if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
                var receipt = Data("{\"page\":".utf8)
                receipt.append(updated); receipt.append(Data(",\"incompatible_references\":[]}".utf8))
                return APIResponse(status: 200, data: receipt)
            }
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
    private func collectionResponse(_ request: APIRequest) throws -> APIResponse {
        let encoder = JSONEncoder()
        if request.path == ["v1", "collections"], request.method == .get {
            struct List: Encodable { let collections: [PageCollection]; let total: Int }
            let values = collections.values.sorted { $0.id < $1.id }
            return APIResponse(status: 200, data: try encoder.encode(List(collections: values, total: values.count)))
        }
        let id = request.path.count == 3 ? request.path[2] : "collection:" + UUID().uuidString.lowercased()
        if request.method == .get {
            guard let value = collections[id] else { throw FiestaBoardError.rejected(status: 404) }
            return APIResponse(status: 200, data: try encoder.encode(value))
        }
        if request.method != .post {
            guard let current = collections[id] else { throw FiestaBoardError.rejected(status: 404) }
            let expected: String?
            if request.method == .delete { expected = request.queryItems.first { $0.name == "expected_revision" }?.value }
            else {
                struct Update: Decodable { let expected_revision: String }
                expected = try JSONDecoder().decode(Update.self, from: request.body!).expected_revision
            }
            guard current.revision == expected, mode != .rejected else { throw FiestaBoardError.collectionConflict }
        } else if mode == .rejected { throw FiestaBoardError.rejected(status: 400) }
        if request.method == .delete {
            collections.removeValue(forKey: id)
            if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
            struct Deleted: Encodable { let id: String }
            return APIResponse(status: 200, data: try encoder.encode(Deleted(id: id)))
        }
        let input = try JSONDecoder().decode(CollectionInput.self, from: request.body!)
        try input.validate()
        guard input.pageIDs.allSatisfy({ pageKeys.contains($0 == "page-selected" ? "page" : $0) }) else { throw FiestaBoardError.rejected(status: 400) }
        let now = ISO8601DateFormatter().string(from: Date())
        let value = PageCollection(id: id, name: input.name, pageIDs: input.pageIDs,
            selectionMode: input.selectionMode.rawValue, time: input.time, variable: input.variable, random: input.random,
            revision: "demo-" + UUID().uuidString, editProtocol: "collection-revision-v1",
            createdAt: collections[id]?.createdAt ?? now, updatedAt: request.method == .put ? now : nil)
        collections[id] = value
        if mode == .unknown || mode == .partial { throw FiestaBoardError.unknownMutationOutcome }
        return APIResponse(status: request.method == .post ? 201 : 200, data: try encoder.encode(value))
    }
    private func reply(_ json: String) -> APIResponse { APIResponse(status: 200, data: Data(json.utf8)) }
}
