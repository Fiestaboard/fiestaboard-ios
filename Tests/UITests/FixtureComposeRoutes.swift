import Foundation

/// I8-only test namespace. H3/catalog/exact-preview responses are recorded bytes.
/// Renamed displays, arbitrary split-flap typing, Page copies and receipt clocks
/// below are synthetic navigation glue, never authenticated hub/hardware evidence.
extension FixtureRouter {
    func composeRecord(_ name: String) -> [String: Any]? {
        composeRecords.first { $0["case"] as? String == name }
    }
    func composeRecordedReply(_ record: [String: Any]) -> Response {
        let data = (record["raw_response"] as? String).map { Data($0.utf8) }
            ?? canonical(record["response"]!)
        return Response(status: record["status"] as! Int, body: data,
                        headers: record["headers"] as? [String: String] ?? [:])
    }
    func composeDetails(_ state: State) -> [[String: Any]] {
        ["hall-1", "note-fixture", "tc001-fixture"].compactMap { id in
            guard var detail = composeRecord("drawing-" + id)?["response"] as? [String: Any] else { return nil }
            detail["name"] = id == "hall-1" ? "Kitchen board" : (id == "tc001-fixture" ? "Entry clock" : "Desk Note")
            if let current = state.boards[id] { detail.merge(current) { _, new in new } }
            return detail
        }
    }
    func composeRoute(_ method: String, _ route: String, _ body: [String: Any],
                      _ boardID: String, _ state: State) -> Response {
        let details = composeDetails(state)
        let segments = route.split(separator: "/").map(String.init)
        if method == "GET", route == "version" {
            var version = cases["version"] as! [String: Any]
            for key in ["version", "running_version", "build_version"] { version[key] = "11.0.0-alpha.3" }
            version["is_dev"] = true
            return reply(200, version, noStore: true)
        }
        if method == "GET", route == "v1/boards" { return reply(200, ["boards": details, "total": details.count]) }
        if segments.count >= 3, segments[0] == "v1", segments[1] == "boards",
           let detail = details.first(where: { $0["id"] as? String == segments[2] }) {
            let id = segments[2]
            if method == "GET", segments.count == 3 { return reply(200, detail, noStore: true) }
            if segments.count == 4, segments[3] == "compose", method == "POST" {
                guard body["protocol"] as? String == "compose-intent-v1",
                      let uuid = body["request_id"] as? String, UUID(uuidString: uuid) != nil,
                      let duration = body["duration"] as? [String: Any],
                      let lines = body["template"] as? [String], !lines.isEmpty else { return reply(422) }
                let key = id + "/" + uuid.lowercased()
                // Duplicate UUID POSTs are refused, never a second synthetic dispatch.
                guard state.composeReceipts[key] == nil else { return reply(409, ["detail": "Synthetic fixture refuses replay"]) }
                state.composePosts += 1
                let unknown = state.composeUnknown || state.composeAmbiguous
                let record = composeRecord(unknown ? "unknown" : (state.composeHeld ? "explicit-hold" : "formatted-timed-primary"))!
                let envelope = record["response"] as! [String: Any]
                var receipt = (envelope["detail"] as? [String: Any]) ?? envelope
                receipt["board_id"] = id; receipt["request_id"] = uuid; receipt["duration"] = duration
                if state.composeHeld {
                    state.boards[id] = ["compose_receipt": ["request_id": uuid, "status": "held"]]
                } else if !unknown {
                    let now = Date(), formatter = ISO8601DateFormatter()
                    receipt["started_at"] = formatter.string(from: now)
                    switch duration["kind"] as? String {
                    case "minutes": receipt["expires_at"] = formatter.string(from: now.addingTimeInterval(Double(duration["minutes"] as? Int ?? 120) * 60))
                    case "until": receipt["expires_at"] = duration["ends_at"]
                    default: receipt["expires_at"] = null
                    }
                    state.boards[id] = ["compose_receipt": ["request_id": uuid, "status": "sent"], "text": lines.joined(separator: "\n")]
                }
                state.composeReceipts[key] = receipt
                // Synthetic malformed success models a thrown decoder after the POST:
                // no fabricated server receipt may stand in for the retained UUID.
                if state.composeAmbiguous { return reply(200, [:], noStore: true) }
                if state.composeHeld { return reply(202, receipt, noStore: true) }
                if unknown { return reply(503, ["detail": receipt], noStore: true) }
                return reply(200, receipt, noStore: true)
            }
            if method == "GET", segments.count == 5, segments[3] == "compose" {
                let key = id + "/" + segments[4].lowercased()
                guard var receipt = state.composeReceipts[key] else { return reply(404) }
                if state.composeHeld, receipt["status"] as? String == "held" {
                    // Explicit GET observes the scenario's synthetic silence release.
                    let now = Date(), formatter = ISO8601DateFormatter()
                    let duration = receipt["duration"] as! [String: Any]
                    receipt["status"] = "sent"; receipt["sent"] = true
                    receipt["started_at"] = formatter.string(from: now)
                    receipt["held_until"] = null; receipt["reason"] = null
                    switch duration["kind"] as? String {
                    case "minutes": receipt["expires_at"] = formatter.string(from: now.addingTimeInterval(Double(duration["minutes"] as? Int ?? 120) * 60))
                    case "until": receipt["expires_at"] = duration["ends_at"]
                    default: receipt["expires_at"] = null
                    }
                    state.composeReceipts[key] = receipt
                    state.boards[id] = ["compose_receipt": ["request_id": receipt["request_id"]!, "status": "sent"]]
                }
                return reply(200, receipt, noStore: true)
            }
        }
        if method == "POST", route == "templates/render" {
            // A recorded request may target the UI alias for the same TC001 geometry.
            let normalizedBody = canonical(normalized(body))
            if let match = composeRecords.first(where: {
                $0["method"] as? String == "POST" && $0["path"] as? String == "/templates/render"
                && ($0["status"] as? Int == 200)
                && ($0["request"] as? [String: Any]).map { canonical(normalized($0)) == normalizedBody } == true
            }) { return composeRecordedReply(match) }
            guard let detail = details.first(where: { $0["id"] as? String == body["board_id"] as? String }),
                  detail["device_type"] as? String != "panel" else {
                return reply(422, ["detail": "Synthetic fixture has no recorded preview for this input"])
            }
            // Existing explicitly synthetic typing renderer; no invented LED frame.
            var rendered = toyRender(body)
            rendered["charset"] = detail["charset"]; rendered["charset_issues"] = []
            return reply(200, rendered)
        }
        if method == "GET", ["v1/variables", "v1/functions", "plugins/date_time/manifest"].contains(route),
           let record = composeRecords.first(where: {
            $0["method"] as? String == "GET" && $0["path"] as? String == "/" + route
            && $0["status"] as? Int == 200
        }) { return composeRecordedReply(record) }
        if method == "POST", route == "displays/raw/batch",
           let denied = composeRecord("mobile-array-batch-denied") { return composeRecordedReply(denied) }
        if method == "POST", route == "templates/validate" {
            if let record = composeRecords.first(where: {
                $0["method"] as? String == "POST" && $0["path"] as? String == "/templates/validate"
                && ($0["status"] as? Int == 200 || $0["status"] as? Int == 422)
                && canonical($0["request"]!) == canonical(body)
            }) { return composeRecordedReply(record) }
            return reply(422, ["detail": "Synthetic fixture has no recorded validation for this expression"])
        }
        if method == "POST", route == "pages" {
            guard let name = body["name"] as? String, !name.isEmpty,
                  let lines = body["template"] as? [String], !lines.isEmpty else { return reply(422) }
            var page = composeRecord("create-hall-1")!["response"] as! [String: Any]
            // Copy request bytes only; no display/Schedule/active-page side effect.
            page.merge(body) { _, new in new }
            page["id"] = "synthetic-compose-page-\(state.extraPages.count + 1)"
            page["revision"] = "synthetic-compose-r1"
            state.extraPages.append(page)
            return reply(201, page, noStore: true)
        }
        if method == "GET", route == "v1/pages" { return reply(200, ["pages": state.extraPages, "total": state.extraPages.count]) }
        if method == "GET", segments.count == 2, segments[0] == "pages",
           let page = state.extraPages.first(where: { $0["id"] as? String == segments[1] }) { return reply(200, page, noStore: true) }
        if method == "GET", route == "settings/display" { return reply(200, ["reduce_motion": false, "board_animations": true, "site_animations": true, "board_flap_speed": "standard"]) }
        if method == "GET", route == "silence-status" { return reply(200, ["enabled": false, "active": false, "board_id": boardID, "mode": null, "page_id": null, "ends_at_utc": null, "holds_blocked_sends": false, "held": null]) }
        if method == "GET", route == "v1/status" { return reply(200, ["running": true, "initialized": true, "boards": [:]]) }
        if method == "GET", route == "v1/schedules" { return reply(200, ["schedules": [], "total": 0, "default_page_id": null, "enabled": false]) }
        if method == "GET", route == "v1/collections" { return reply(200, ["collections": [], "total": 0]) }
        return reply(404)
    }
}
