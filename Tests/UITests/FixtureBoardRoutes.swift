import Foundation
import CoreFoundation


extension FixtureRouter {
    var collection: [String: Any] { seed["collection"] as! [String: Any] }
    var collectionID: String { "collection:" + (collection["id"] as! String) }
    func frame(_ lines: [String], _ rows: Int, _ cols: Int) -> [[Int]] {
        let chars = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#$()\0-\0+&=;:\0'\"%,.\0\0/?\0")
        return (0..<rows).map { row in
            let source = row < lines.count ? lines[row] : ""
            let cells = markerCells(source)
            let encoded = cells.map { token -> Int in
                if token.hasPrefix("{"), let code = Int(token.dropFirst().dropLast()) { return code }
                if token == "°" || token == "♥" { return 62 }
                return token.uppercased().first.flatMap { chars.firstIndex(of: $0) } ?? 0
            }
            let left = max(0, (cols-min(cols, encoded.count))/2)
            return Array((Array(repeating: 0, count: left) + encoded + Array(repeating: 0, count: cols)).prefix(cols))
        }
    }
    func frameText(_ grid: [[Int]]) -> String {
        let chars = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#$()\0-\0+&=;:\0'\"%,.\0\0/?\0")
        return grid.map { row in
            var value = row.map { code in code == 62 ? "°" : (code >= 63 || code == 0 || code >= chars.count ? " " : String(chars[code])) }.joined()
            while value.hasSuffix(" ") { value.removeLast() }; return value
        }.joined(separator: "\n")
    }
    func currentPage(_ state: State, _ id: String) -> [String: Any]? {
        if let saved = state.savedPages[id] { return saved }
        if var page = pages.first(where: { $0["id"] as? String == id }) { page.removeValue(forKey: "shows"); return page }
        return state.extraPages.first { $0["id"] as? String == id }
    }
    func pageFrame(_ id: String, _ rows: Int, _ cols: Int) -> [[Int]] { frame(pages.first { $0["id"] as? String == id }?["shows"] as? [String] ?? ["NO PAGE"], rows, cols) }
    func boardSummary(_ entry: [String: Any], _ state: State) -> [String: Any] {
        var summary = entry["summary"] as! [String: Any]; let live = state.boards[summary["id"] as! String]!
        for key in ["paused", "schedule_enabled", "auto_restore"] { summary[key] = live[key] }; return summary
    }
    func boardDetail(_ entry: [String: Any], _ state: State) -> [String: Any] {
        let summary = entry["summary"] as! [String: Any], id = summary["id"] as! String
        var live = state.boards[id]!, out = boardSummary(entry, state)
        let rows = summary["rows"] as! Int, cols = summary["cols"] as! Int
        let active = live["active_page_id"] as? String
        let scheduled: String? = id == "kitchen" && live["schedule_enabled"] as? Bool == true ? (["schedule", "override"].contains(state.scenario) ? "hello" : (state.scenario.hasPrefix("collection") ? collectionID : nil)) : nil
        var shown = active ?? scheduled
        if shown == collectionID {
            shown = state.scenario == "collection-native-null" ? nil : (collection["page_ids"] as! [String])[Int(Date().timeIntervalSince(state.started)/2) % 2]
        }
        if id == "kitchen", let shown, pages.contains(where: { $0["id"] as? String == shown }) { live["characters"] = pageFrame(shown, rows, cols); state.boards[id] = live }
        let expected = live["characters"] as! [[Int]]
        let shownGrid = id == "kitchen" && state.sync["foreign"] == true ? frame(["", "SOMEONE ELSE", "WAS HERE {red}{red}", "", "SENT FROM A PHONE APP"], rows, cols) : expected
        out.merge(["characters": shownGrid, "text": frameText(shownGrid), "expected_characters": expected, "read_at": null,
                   "active_page_id": active as Any? ?? null, "scheduled_page_id": scheduled as Any? ?? null,
                   "resolved_page_id": shown as Any? ?? null, "resolved_next_check_seconds": (active ?? scheduled) == collectionID ? 2 as Any : null,
                   "source": active != nil ? "manual" : (scheduled != nil ? "schedule" : "none"), "default_page_id": null,
                   "override_expires_at": id == "kitchen" && state.scenario == "override" && !state.overrideCleared ? "2026-10-31T09:09:00Z" as Any : null,
                   "layers": id == "pixoo" ? [["x": 40, "y": 2, "width": 2, "height": 2, "rgba": "AP8A/wD/AP8A/wD/AP8A/w=="]] as Any : null]) { _, new in new }
        if state.homeContract {
            // New I7 synthetic cases reuse the actual H1/H2 shapes; legacy
            // migration-control bytes remain unchanged in their own namespace.
            let activeOverride = id == "kitchen" && state.scenario == "override" && !state.overrideCleared
            out["override_started_at"] = activeOverride ? ISO8601DateFormatter().string(from: state.started) as Any : null
            if activeOverride { out["override_expires_at"] = ISO8601DateFormatter().string(from: state.started.addingTimeInterval(540)) }
            out["next_change_at"] = id == "kitchen" && state.scenario == "schedule" ? ISO8601DateFormatter().string(from: state.started.addingTimeInterval(3600)) as Any : null
            out["next_change_reason"] = id == "kitchen" && state.scenario == "schedule" ? "schedule" as Any : null
            out["next_page_id"] = id == "kitchen" && state.scenario == "schedule" ? "morning" as Any : null
            out["health"] = ["reachable": null, "last_error": null, "breaker_open": false]
        }
        return out
    }
    func boardRoute(_ method: String, _ route: String, _ body: [String: Any], _ boardID: String, _ state: State, undoRequested: Bool = false) -> Response? {
        if state.boards.isEmpty {
            for entry in boards {
                let s = entry["summary"] as! [String: Any], id = s["id"] as! String
                let mapped = (seed["boardPages"] as! [String: [Any]])[id]?.first as? String
                var active: Any = state.scenario == "no-pages" ? null : (mapped as Any? ?? null)
                if id == "kitchen" {
                    if ["manual", "paused", "silence", "silence-held", "out-of-sync", "overwritten", "kept"].contains(state.scenario) { active = "hello" }
                    else if state.scenario.hasPrefix("collection") { active = collectionID }
                }
                state.boards[id] = ["paused": state.scenario == "paused", "schedule_enabled": ["schedule", "collection", "override"].contains { state.scenario.hasPrefix($0) }, "auto_restore": true, "active_page_id": active,
                                    "characters": frame(entry["lines"] as! [String], s["rows"] as! Int, s["cols"] as! Int)]
            }
        }
        let segments = route.split(separator: "/").map(String.init)
        let selected = boards.first { ($0["summary"] as! [String: Any])["id"] as? String == boardID }
        if method == "GET", route == "version" { let version = state.homeContract ? "11.0.0-alpha.3" : "10.1.20"; return reply(200, ["package_version": version, "build_version": version, "running_version": version, "is_dev": false, "hardware_model": null]) }
        if method == "GET", route == "v1/boards" { let entries = state.scenario == "no-boards" ? [] : boards.map { boardSummary($0, state) }; return reply(200, ["boards": entries, "total": entries.count]) }
        if segments.count >= 3, segments[0] == "v1", segments[1] == "boards" {
            guard let entry = boards.first(where: { ($0["summary"] as! [String: Any])["id"] as? String == segments[2] }) else { return reply(404, ["detail": "Board not found"]) }
            let s = entry["summary"] as! [String: Any], id = s["id"] as! String
            if method == "GET", segments.count == 3 { return reply(200, boardDetail(entry, state)) }
            if method == "PUT", segments.last == "active-page" {
                if state.homeContract && state.scenario == "home-unknown" { return reply(503, ["detail":"Synthetic unconfirmed Home mutation"]) }
                if state.homeContract && state.scenario == "home-delayed", !homeMutationGate.waitForRelease() {
                    return reply(503, ["detail":"Synthetic Home mutation gate timed out"])
                }
                let page = body["page_id"] as? String; state.boards[id]!["active_page_id"] = page as Any? ?? null
                let sent = state.boards[id]!["paused"] as? Bool != true
                if sent, let page { state.boards[id]!["characters"] = pageFrame(page, s["rows"] as! Int, s["cols"] as! Int) }
                return reply(200, ["board_id": id, "page_id": page as Any? ?? null, "sent": sent, "silenced": false, "reason": sent ? null : "paused" as Any, "error": null, "warnings": []])
            }
            if method == "POST", segments.last == "restore" {
                if id == "kitchen" { state.sync = ["foreign": false, "overwritten": false, "kept": false] }
                let sent = state.boards[id]!["paused"] as? Bool != true
                return reply(200, ["board_id": id, "page_id": state.boards[id]!["active_page_id"]!, "sent": sent, "reason": sent ? null : "paused" as Any, "device_observed": false])
            }
        }
        if method == "DELETE", route == "settings/temporary-override" {
            if state.homeContract && boardID != "kitchen" { return reply(200, ["revert_mode": null]) }
            let was = state.scenario == "override" && !state.overrideCleared; state.overrideCleared = true
            var result: [String: Any] = ["revert_mode": was ? "schedule" as Any : null]
            if state.homeContract && undoRequested {
                state.undoToken = was ? "synthetic-ui-undo" : nil
                state.undoDeadline = was ? Date().addingTimeInterval(30) : nil
                result["undo_token"] = state.undoToken as Any? ?? null
                result["undo_expires_at"] = state.undoDeadline.map { ISO8601DateFormatter().string(from:$0) } as Any? ?? null
            }
            return reply(200,result, noStore: state.homeContract)
        }
        if state.homeContract, method == "GET", route == "settings/temporary-override" {
            return reply(200,["undo_supported":true,"active":boardID == "kitchen" && state.scenario == "override" && !state.overrideCleared,"board_id":boardID], noStore:true)
        }
        if state.homeContract, method == "POST", route == "settings/temporary-override/undo" {
            guard body["board_id"] as? String == "kitchen", let value = state.undoToken,
                  body["undo_token"] as? String == value, let end = state.undoDeadline, end > Date() else { return reply(409,["detail":"Undo unavailable"]) }
            state.undoToken = nil; state.undoDeadline = nil; state.overrideCleared = false
            return reply(200,["undo_supported":true,"active":true,"board_id":"kitchen","page_id":"note","started_at":"2026-10-31T09:00:00Z","expires_at":"2026-10-31T09:09:00Z"], noStore:true)
        }
        if method == "DELETE", route == "board/external-frame" { if boardID == "kitchen" { state.sync["kept"] = false }; return reply(204) }
        if method == "POST", route == "v1/pages" {
            var page = seed["pageCommon"] as! [String: Any]
            page.merge(["id": "saved-\(state.extraPages.count+1)", "name": body["name"] ?? null, "type": "template", "device_type": body["device_type"] as? String ?? "flagship", "template": body["template"] ?? [], "grid_rows": body["grid_rows"] ?? null, "grid_cols": body["grid_cols"] ?? null, "revision": "revision-new-1"]) { _, new in new }; state.extraPages.append(page); return reply(201, page)
        }
        if method == "GET", route == "settings/board" {
            let result = boards.map { entry -> [String: Any] in
                let s = entry["summary"] as! [String: Any], id = s["id"] as! String, live = state.boards[id]!
                var b: [String: Any] = ["id": id, "name": s["name"]!, "device_type": s["device_type"]!, "board_color": "black", "code62_glyph": "degree", "enabled": true, "paused": live["paused"]!, "schedule_enabled": live["schedule_enabled"]!, "polling_interval_seconds": 15, "board_read_interval_local": 30, "board_read_interval_cloud": 180, "schedule_defer_on_reenable": false, "auto_restore": live["auto_restore"]!, "notes_wide": 1, "notes_tall": 1, "grid_rows": null, "grid_cols": null, "output": s["output"]!, "output_config": [String: Any]()]
                if let model = s["device_model"] as? String, !["vestaboard", "fiestapanel"].contains(s["output"] as! String) { b["device_model"] = model }
                b.merge(entry["stored"] as! [String: Any]) { _, new in new }; return b
            }
            return reply(200, ["board_type": null, "devices": boards.map { ($0["summary"] as! [String: Any])["device_type"]! }, "boards": result])
        }
        if method == "GET", route == "v1/status" {
            var out: [String: Any] = [:]
            for entry in boards { let id = (entry["summary"] as! [String: Any])["id"] as! String, live = state.boards[id]!
                out[id] = ["configured": entry["error"] == nil, "paused": live["paused"]!, "active_page_id": live["active_page_id"]!, "error": entry["error"] ?? null, "output_status": ["state": entry["not_configured"] as? Bool == true ? "not_configured" : "connected", "message": entry["not_configured"] as? Bool == true ? "Not configured" : "Settings look complete"]]
            }; return reply(200, ["running": true, "initialized": true, "boards": out])
        }
        if method == "GET", route == "board/current-message" {
            guard let selected else { return reply(404, ["detail": "Board not found"]) }; let d = boardDetail(selected, state)
            var out: [String: Any] = ["characters": d["characters"]!, "message": d["text"]!, "rows": d["rows"]!, "cols": d["cols"]!, "expected_characters": d["expected_characters"]!, "cached_at": "2026-10-31T08:15:00Z", "api_mode": "local"]
            if boardID == "kitchen", state.sync["overwritten"] == true { out["overwritten_at"] = "2026-10-31T16:12:00+00:00" }
            if boardID == "kitchen", state.sync["kept"] == true { out["external_characters"] = frame(["", "SOMEONE ELSE", "WAS HERE {red}{red}", "", "SENT FROM A PHONE APP"], d["rows"] as! Int, d["cols"] as! Int); out["external_detected_at"] = "2026-10-31T16:12:00+00:00" }
            if boardID == "pixoo" { out["layers"] = d["layers"] }; return reply(200, out)
        }
        if method == "GET", ["schedules/active/page", "settings/active-page"].contains(route) {
            guard let selected else { return reply(404, ["detail": "Board not found"]) }; let d = boardDetail(selected, state)
            var out: [String: Any] = ["page_id": d["active_page_id"] is NSNull ? d["scheduled_page_id"]! : d["active_page_id"]!, "resolved_page_id": d["resolved_page_id"]!, "resolved_next_check_seconds": d["resolved_next_check_seconds"]!]
            if route == "settings/active-page" { out["board_id"] = boardID; return reply(200, out) }
            out["schedule_enabled"] = state.boards[boardID]!["schedule_enabled"]!
            let override = state.scenario == "override" && !state.overrideCleared && boardID == "kitchen"
            out["temporary_override"] = ["active": override, "page_id": override ? "note" as Any : null, "expires_at": override ? "2026-10-31T09:09:00Z" as Any : null, "remaining_seconds": override ? 540 as Any : null, "revert_mode": override ? "schedule" as Any : null]; return reply(200, out)
        }
        if method == "GET", route == "silence-status" {
            if !state.homeContract {
                let active = state.scenario == "silence"
                return reply(200,["enabled":active,"active":active,"mode":active ? "indicator" as Any : null,"page_id":null,
                    "ends_at_utc":active ? "2026-10-31T14:00:00Z" as Any : null,"next_change_utc":null,
                    "seconds_until_next_change":null,"holds_blocked_sends":false,"held":null])
            }
            let active = state.scenario.hasPrefix("silence") && boardID == "kitchen"
            let held: Any = active && state.scenario == "silence-held"
                ? ["kind":"text","preview":"Package delivered","queued_at":ISO8601DateFormatter().string(from:state.started)] : null
            return reply(200,["enabled":active,"active":active,"board_id":boardID,"mode":active ? "indicator" as Any : null,
                "page_id":null,"ends_at_utc":active ? ISO8601DateFormatter().string(from:state.started.addingTimeInterval(3600)) as Any : null,
                "holds_blocked_sends":active,"held":held])
        }
        if state.homeContract, method == "POST", segments.count == 4,
           segments[0] == "settings", segments[1] == "board", segments[3] == "pause",
           body["paused"] as? Bool == false, state.boards[segments[2]] != nil {
            state.boards[segments[2]]!["paused"] = false
            return reply(200,["board_id":segments[2],"paused":false])
        }
        if method == "GET", route == "settings/display" { return reply(200, ["reduce_motion": false, "board_animations": true, "site_animations": true, "board_flap_speed": "standard"]) }
        if method == "GET", route == "v1/pages" { let ids = (state.scenario == "no-pages" ? [] : pages.compactMap { $0["id"] as? String }) + state.extraPages.compactMap { $0["id"] as? String }; return reply(200, ["pages": ids.compactMap { currentPage(state, $0) }, "total": ids.count]) }
        if segments.count >= 3, segments[0] == "v1", segments[1] == "pages" {
            if method == "PUT", segments.count == 3 { return savePage(state, segments[2], body) }
            if method == "GET" { return currentPage(state, segments[2]).map { reply(200, $0) } ?? reply(404, ["detail": "Page not found"]) }
        }
        if method == "GET", route == "v1/schedules" {
            let entries: [[String: Any]] = state.scenario == "schedule-gap" ? [] : (seed["schedules"] as! [[String]]).map { values in
                ["id": values[0], "revision": "revision-" + values[0], "board_id": boardID, "page_id": values[1], "start_time": values[2], "end_time": values[3], "day_pattern": values[4], "custom_days": null, "enabled": true, "recurrence_type": "weekly", "annual_date": null, "annual_end_date": null, "one_off_date": null, "one_off_end_date": null, "start_type": "fixed", "start_sun_offset": 0, "end_type": "fixed", "end_sun_offset": 0, "created_at": "2026-10-31T08:00:00Z", "updated_at": null, "resolved_start_time": values[2], "resolved_end_time": values[3], "warnings": [], "edit_protocol": "schedule-revision-v1"]
            }; return reply(200, ["schedules": entries, "total": entries.count, "default_page_id": null, "enabled": state.boards[boardID]?["schedule_enabled"] ?? false])
        }
        if method == "GET", route == "v1/collections" { return reply(200, ["collections": [collection], "total": 1]) }
        if method == "GET", route == "v1/collections/" + (collection["id"] as! String) { return reply(200, collection) }
        return nil
    }
    func savePage(_ state: State, _ id: String, _ body: [String: Any]) -> Response {
        guard var page = currentPage(state, id) else { return reply(404, ["detail": "Page not found"]) }
        guard page["edit_protocol"] as? String == "page-revision-v1" else { return reply(409, ["detail": "This page type is not editable through the revision protocol"]) }
        guard body["expected_revision"] as? String == page["revision"] as? String else { return reply(412, ["detail": "Page changed; fetch for comparison"]) }
        let unknown = Set(body.keys).subtracting(["expected_revision", "name", "template", "line_metadata", "canvases", "device_type", "notes_wide", "notes_tall", "grid_rows", "grid_cols", "display_type", "rows"])
        if !unknown.isEmpty { return reply(422, ["detail": "Unsupported page patch fields: " + unknown.sorted().joined(separator: ", ")]) }
        if let value = body["template"], (value as? [String])?.isEmpty != false { return reply(422, ["detail": "Template pages require at least one template line"]) }
        if let value = body["canvases"], !(value is NSNull) {
            guard let canvases = value as? [[String: Any]], canvases.count <= 8, canvases.allSatisfy({ ($0["id"] as? String)?.isEmpty == false }) else { return reply(422, ["detail": "Invalid canvases"]) }
            for canvas in canvases { let area = canvas["area"] as? [String: Any] ?? [:]
                guard ["row", "col", "rows", "cols"].allSatisfy({ key in guard let n = area[key] as? NSNumber else { return false }; return CFGetTypeID(n) != CFBooleanGetTypeID() && n.doubleValue.rounded() == n.doubleValue && n.intValue >= 1 }) else { return reply(422, ["detail": "Canvas area values must be whole numbers >= 1"]) }
            }
        }
        for (key,value) in body where key != "expected_revision" { page[key] = value }
        state.saveCount += 1; page["revision"] = "revision-\(id)-saved-\(state.saveCount)"; page["updated_at"] = String(format: "2026-11-02T09:%02d:00Z", state.saveCount % 60); state.savedPages[id] = page
        return reply(200, ["page": page, "incompatible_references": []])
    }
}
