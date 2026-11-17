import Foundation

/// Test-only router. All mutations are confined to one prefix; the listener serializes access.
/// Existing synthetic editor artwork is explicitly separated from recorded mobile auth fixtures.
final class FixtureRouter {
    struct Response {
        let status: Int
        let body: Data
        var headers: [String: String] = [:]
    }
    final class State {
        let scenario: String
        let homeContract: Bool
        let composeUnknown: Bool
        let composeAmbiguous: Bool
        let composeHeld: Bool
        var mode: String
        var setup: Bool
        var token: String?
        var boards: [String: [String: Any]] = [:]
        var savedPages: [String: [String: Any]] = [:]
        var extraPages: [[String: Any]] = []
        var saveCount = 0
        // Synthetic I8 lifecycle state; recorded corpus bytes remain immutable.
        var composeReceipts: [String: [String: Any]] = [:]
        var composePosts = 0
        var flexible: [String: Any]
        var flexibleRevision = 1
        var sync: [String: Bool]
        var overrideCleared = false
        var undoToken: String?
        var undoDeadline: Date?
        let started = Date()
        init(prefix: String, flexible: [String: Any]) {
            self.flexible = flexible
            homeContract = prefix.hasPrefix("/board-i7-")
            composeUnknown = prefix.hasPrefix("/board-i8-compose-unknown-")
            composeAmbiguous = prefix.hasPrefix("/board-i8-compose-ambiguous-")
            composeHeld = prefix.hasPrefix("/board-i8-compose-held-")
            setup = prefix.hasPrefix("/setup-")
            mode = prefix.hasPrefix("/mixed-") || prefix.hasPrefix("/flexible-") ? "disabled" : (setup ? "undecided" : "enabled")
            let rawScenario = prefix.hasPrefix("/board-") ? String(prefix.dropFirst(7).split(separator: "-").dropLast().joined(separator: "-")) : "manual"
            scenario = homeContract ? String(rawScenario.dropFirst(3)) : rawScenario
            sync = ["foreign": scenario == "out-of-sync", "overwritten": scenario == "overwritten", "kept": scenario == "kept"]
        }
    }
    let homeMutationGate = FixtureHomeMutationGate()
    let seed: [String: Any]
    var recorded: [String: (method: String, path: String, response: Response)] = [:]
    var states: [String: State] = [:]
    var composeRecords: [[String: Any]] = []
    let null = NSNull()
    var boards: [[String: Any]] { seed["boards"] as! [[String: Any]] }
    var pages: [[String: Any]] { seed["pages"] as! [[String: Any]] }
    var cases: [String: Any] { seed["cases"] as! [String: Any] }
    init(resourceURL: URL, recordedURL: URL? = nil) throws {
        seed = try JSONSerialization.jsonObject(with: Data(contentsOf: resourceURL)) as! [String: Any]
        if let recordedURL {
            for file in ["operations-authenticated.json", "long-led-authenticated.json", "compose-authenticated.json", "catalog-authenticated.json"] {
                let url = recordedURL.appendingPathComponent("Compose").appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) {
                    let corpus = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
                    composeRecords += corpus["records"] as! [[String: Any]]
                }
            }
            let source = try JSONSerialization.jsonObject(with: Data(contentsOf: recordedURL.appendingPathComponent("SOURCE.json"))) as! [String: Any]
            for record in source["responses"] as! [[String: Any]] {
                let file = record["file"] as! String
                let response = Response(status: record["status"] as! Int, body: try Data(contentsOf: recordedURL.appendingPathComponent(file)), headers: record["headers"] as! [String: String])
                recorded[String(file.dropLast(5))] = (record["method"] as! String, record["path"] as! String, response)
            }
        }
    }
    func reply(_ status: Int = 200, _ body: Any = [String: Any](), noStore: Bool = false) -> Response {
        Response(status: status, body: status == 204 ? Data() : (try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .fragmentsAllowed])), headers: noStore ? ["Cache-Control":"no-store"] : [:])
    }
    func respond(method: String, target: String, headers: [String: String], body raw: Data) -> Response {
        let parts = target.components(separatedBy: "?"); let path = parts[0]
        let query = URLComponents(string: "http://fixture/?" + (parts.count > 1 ? parts[1] : ""))?.queryItems ?? []
        let boardID = query.first { $0.name == "board_id" }?.value ?? "kitchen"
        if path == "/ready" { return reply(200, ["fixture": "native-onboarding"]) }
        if method == "GET", path.hasPrefix("/fixture-state/") {
            let items = path.split(separator: "/").map(String.init)
            guard items.count == 4, items[2] == "pages", let state = states["/" + items[1]], let page = currentPage(state, items[3]) else { return reply(404) }
            return reply(200, page)
        }
        let routeParts = path.components(separatedBy: "/api/")
        if routeParts.count == 2, routeParts[0].hasPrefix("/recorded-") {
            let variant = String(routeParts[0].dropFirst(10))
            guard let item = recorded[variant], item.method == method, item.path == "/" + routeParts[1] else { return reply(404) }
            return item.response
        }
        guard routeParts.count == 2, ["/signin-", "/setup-", "/mixed-", "/flexible-", "/board-"].contains(where: { routeParts[0].hasPrefix($0) }) else { return reply(404) }
        let prefix = routeParts[0], route = routeParts[1]
        let state = states[prefix] ?? State(prefix: prefix, flexible: seed["flexible"] as! [String: Any]); states[prefix] = state
        let body: [String: Any]
        if raw.isEmpty { body = [:] } else {
            guard let decoded = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return reply(400) }; body = decoded
        }
        let authorization = headers.first { $0.key.lowercased() == "authorization" }?.value
        let authenticated = state.token != nil && authorization == "Bearer " + state.token!
        if method == "GET", route == "health" { return reply(200, cases["health"]!) }
        if method == "GET", route == "discover" { return reply(200, ["product": "FiestaBoard", "version": prefix.hasPrefix("/board-i8-compose-") ? "11.0.0-alpha.3" : "11.0.0", "id": String(prefix.dropFirst()), "name": "UI Test Server"]) }
        if method == "GET", route == "auth/status" {
            var status = cases[authenticated ? "auth_authenticated" : "auth_enabled"] as! [String: Any]
            status.merge(["mode": state.mode, "first_run": state.mode == "undecided", "enabled": state.mode != "disabled", "setup_required": state.setup && state.mode != "disabled", "username": authenticated ? "fixture_admin" as Any : null, "authenticated": authenticated, "auth_kind": authenticated ? "mobile" as Any : null]) { _, new in new }
            return reply(200, status)
        }
        if method == "POST", route == "auth/preference", state.mode == "undecided" { state.mode = body["enabled"] as? Bool == true ? "enabled" : "disabled"; return reply(200, ["status": "ok"]) }
        if method == "POST", ["auth/setup", "auth/device/login", "auth/login", "auth/pairing/claim"].contains(route) {
            if route != "auth/pairing/claim", body["username"] as? String != "fixture_admin" || body["password"] as? String != "fixture-password" { return reply(401, cases["login_wrong"]!) }
            if route == "auth/setup", !state.setup { return reply(409, cases["setup_duplicate"]!) }
            if route == "auth/setup" { state.setup = false }
            let token = "fb_mob_fixture_" + prefix.dropFirst(); state.token = token
            return reply(route == "auth/setup" ? 201 : 200, ["status": "ok", "username": "fixture_admin", "access_token": token, "token_type": "Bearer", "expires_in": 31536000, "session_id": "fixture-" + prefix.dropFirst(), "scope": "control"])
        }
        if (method == "DELETE" && route == "auth/device/session") || (method == "POST" && route == "auth/logout") {
            guard authenticated else { return reply(401, cases["protected_unauthenticated"]!) }; state.token = nil; return reply(200, ["status": "ok"])
        }
        if state.mode != "disabled", !authenticated { return reply(401, cases["protected_unauthenticated"]!) }
        if prefix.hasPrefix("/board-i8-compose-") { return composeRoute(method, route, body, boardID, state) }
        if prefix.hasPrefix("/board-"), let result = boardRoute(method, route, body, boardID, state,
            undoRequested: query.first { $0.name == "undo" }?.value == "true") { return result }
        if !prefix.hasPrefix("/mixed-"), let result = renderRoute(method, route, body, prefix) { return result }
        if prefix.hasPrefix("/board-"), let result = catalogRoute(method, route, body, state) { return result }
        if method == "GET", route == "version" { var version = cases["version"] as! [String: Any]; version["build_version"] = "10.1.20"; version["is_dev"] = false; return reply(200, version) }
        if method == "GET", route == "v1/boards" { return reply(200, cases["boards_list"]!) }
        if method == "GET", route == "v1/boards/contract-board" { return reply(200, cases["boards_detail"]!) }
        if method == "GET", route == "v1/pages/id-2" { return reply(200, cases["page_get"]!) }
        if method == "GET", route == "v1/pages/flexible" { return reply(200, state.flexible) }
        if method == "PUT", route == "v1/pages/flexible" {
            guard body["expected_revision"] as? String == state.flexible["revision"] as? String else { return reply(412, ["detail": "Page changed; fetch for comparison"]) }
            if !Set(body.keys).subtracting(["expected_revision", "name", "blocks", "style", "layout", "targets"]).isEmpty { return reply(422, ["detail": "Unsupported page patch fields"]) }
            if let blocks = body["blocks"] as? [Any], blocks.isEmpty { return reply(422, ["detail": "Flexible page requires at least one block"]) }
            for (key,value) in body where key != "expected_revision" && !(key == "blocks" && value is NSNull) { state.flexible[key] = value }
            state.flexibleRevision += 1; state.flexible["revision"] = "flex-r\(state.flexibleRevision)"
            return reply(200, ["page": state.flexible, "incompatible_references": []])
        }
        if method == "POST", route == "pages/preview/flexible" { return flexiblePreview(body) }
        if prefix.hasPrefix("/mixed-"), method == "POST", route == "templates/render" {
            var pixels: [UInt8] = Array(repeating: [0,0,0,255], count: 32*8).flatMap { $0 }; pixels.replaceSubrange(0..<4, with: [255,128,64,255]); pixels.replaceSubrange((pixels.count-4)..<pixels.count, with: [64,128,255,255])
            return reply(200, ["rendered": "", "lines": [""], "line_count": 1, "charset": "ascii", "charset_issues": [], "canvas_issues": [], "layers": [["x": 0, "y": 0, "width": 32, "height": 8, "physical_frame_version": 1, "rgba": Data(pixels).base64EncodedString()]]])
        }
        if method == "GET", route == "v1/pages" {
            var result: [Any] = [cases["page_get"]!]
            if prefix.hasPrefix("/mixed-") || prefix.hasPrefix("/flexible-") { result += [state.flexible, ["id": "future", "name": "Future document", "type": "future", "document_protocol": "page-document-v99", "revision": "future-r1"]] }
            return reply(200, ["pages": result, "total": result.count])
        }
        return reply(404)
    }
    func catalogRoute(_ method: String, _ route: String, _ body: [String: Any], _ state: State) -> Response? {
        let disabled = state.scenario == "no-plugins"
        if method == "POST", route == "displays/raw/batch" {
            guard let types = body["display_types"] as? [String], !types.isEmpty else { return reply(400, ["detail": "display_types parameter required"]) }
            var displays: [String: Any] = [:]; let raw = seed["raw"] as! [String: Any]
            for name in types where !disabled { if let value = raw[name] { displays[name] = ["data": value, "available": true, "error": null] } }
            return reply(200, ["displays": displays, "total": types.count, "successful": displays.count])
        }
        guard method == "GET" else { return nil }
        if route == "v1/variables" { var vars = seed["variables"] as! [String: Any]; if disabled { for key in ["variables", "max_lengths", "variable_metadata", "variable_groups"] { vars[key] = [String: Any]() } }; return reply(200, vars) }
        if route == "v1/functions" { return reply(200, ["functions": seed["functions"]!]) }
        if route.hasPrefix("plugins/"), route.hasSuffix("/manifest") {
            let plugin = String(route.dropFirst(8).dropLast(9)); if !disabled, let manifest = (seed["manifests"] as! [String: Any])[plugin] { return reply(200, manifest) }
            return reply(404, ["detail": "Plugin not found: " + plugin])
        }
        return nil
    }
    func flexiblePreview(_ body: [String: Any]) -> Response {
        if let board = body["board_id"] as? String, board != "contract-board" { return reply(404, ["detail": "Board not found"]) }
        let page = body["page"] as? [String: Any] ?? [:]
        let gridFields: Set<String> = ["device_type", "notes_wide", "notes_tall", "grid_rows", "grid_cols", "display_type", "rows", "template", "line_metadata", "canvases"]
        guard page["type"] as? String == "flexible", gridFields.isDisjoint(with: page.keys), let blocks = page["blocks"] as? [[String: Any]], !blocks.isEmpty else { return reply(422, ["detail": "Invalid flexible author content"]) }
        if let targets = page["targets"] as? [String: Any], let ids = targets["boards"] as? [String], !ids.contains("contract-board") { return reply(422, ["detail": "Page does not target this board"]) }
        var pixels: [UInt8] = Array(repeating: [0,0,0,255], count: 32*16).flatMap { $0 }
        for y in 2..<14 { for x in 3..<29 { pixels.replaceSubrange(((y*32+x)*4)..<((y*32+x)*4+4), with: [255, x < 16 ? 128 : 255, 64,255]) } }
        let text = blocks.filter { $0["kind"] as? String == "text" }.map { $0["text"] as? String ?? "" }.joined(separator: "\n")
        return reply(200, ["available": true, "page_id": "unsaved", "message": text, "lines": text.components(separatedBy: "\n"), "display_type": "panel", "raw": [String: Any](), "layout_issues": [["path": ["blocks", "retained"], "code": "block_kind_unsupported", "severity": "warning", "message": "Synthetic fixture: retained unknown block is not drawn."]], "canvas_issues": [], "layers": [["x": 0, "y": 0, "width": 32, "height": 16, "physical_frame_version": 1, "rgba": Data(pixels).base64EncodedString()]]])
    }
}

/// Only the I7 delayed UI scenario uses this thread-safe gate. Timeout is a
/// failed test dependency, not a successful write; every test releases it.
final class FixtureHomeMutationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var held = false
    private var waiting = false
    var isWaiting: Bool { condition.lock(); defer { condition.unlock() }; return waiting }
    func setHeld(_ value: Bool) { condition.lock(); held = value; if !value { condition.broadcast() }; condition.unlock() }
    func waitForRelease() -> Bool {
        condition.lock(); defer { condition.unlock() }
        waiting = true; defer { waiting = false }
        let deadline = Date().addingTimeInterval(8)
        while held { if !condition.wait(until: deadline) { return false } }
        return true
    }
}
