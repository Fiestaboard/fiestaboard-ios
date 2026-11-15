import Foundation

extension FixtureRouter {
    var colorCodes: [String: Int] { ["red": 63, "orange": 64, "yellow": 65, "green": 66, "blue": 67, "violet": 68, "purple": 68, "white": 69, "black": 70, "filled": 71] }
    func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] { (try! NSRegularExpression(pattern: pattern)).matches(in: text, range: NSRange(text.startIndex..., in: text)) }
    func substring(_ text: String, _ range: NSRange) -> String { Range(range, in: text).map { String(text[$0]) } ?? "" }
    func replaced(_ text: String, _ pattern: String, _ template: String) -> String { (try! NSRegularExpression(pattern: pattern)).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template) }
    func markerCells(_ text: String) -> [String] {
        var result: [String] = [], pos = text.startIndex
        for match in matches(#"(?i)\{(\d{1,2}|red|orange|yellow|green|blue|violet|purple|white|black|filled)\}"#, text) {
            let range = Range(match.range, in: text)!; result += text[pos..<range.lowerBound].map(String.init)
            let name = substring(text, match.range(at: 1)).lowercased()
            let code = colorCodes[name] ?? Int(name)
            if let code, (63...71).contains(code) { result.append("{\(code)}") } else { result += text[range].map(String.init) }
            pos = range.upperBound
        }
        return result + text[pos...].map(String.init)
    }
    func expandToken(_ inner: String) -> String {
        let stripped = inner.trimmingCharacters(in: .whitespaces), name = stripped.lowercased()
        if let code = colorCodes[name] { return "{\(code)}" }
        if let code = Int(name), (63...71).contains(code) { return "{\(code)}" }
        if stripped.hasPrefix("=") { return (seed["formulaValues"] as! [String: String])[String(stripped.dropFirst()).trimmingCharacters(in: .whitespaces)] ?? "???" }
        let parts = stripped.components(separatedBy: "|"); let key = replaced(parts[0].trimmingCharacters(in: .whitespaces), #"\[(\d+)\]"#, ".$1")
        guard var value = (seed["values"] as! [String: String])[key] else { return "???" }
        for filter in parts.dropFirst() {
            let spec = filter.trimmingCharacters(in: .whitespaces).components(separatedBy: ":"), op = spec[0].lowercased()
            if op == "upper" { value = value.uppercased() } else if op == "lower" { value = value.lowercased() }
            else if spec.count > 1, let width = Int(spec[1]), width >= 0 {
                if op == "pad" { value = String((value + String(repeating: " ", count: max(0, width-value.count))).prefix(width)) }
                if op == "truncate" { value = String(value.prefix(width)) }
                if op == "zeropad", width > 0 { if value.hasPrefix("-") { let tail = String(value.dropFirst()); value = "-" + String(repeating: "0", count: max(0, width-1-tail.count)) + tail } else { value = String(repeating: "0", count: max(0,width-value.count)) + value } }
            }
        }
        return value
    }
    func renderRow(_ source: String, cols: Int) -> [String] {
        var result: [String] = [], fills: [(Int,String)] = [], pos = source.startIndex
        for match in matches(#"\{\{(.*?)\}\}"#, source) {
            let range = Range(match.range, in: source)!; result += markerCells(String(source[pos..<range.lowerBound]))
            let inner = substring(source, match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if inner.lowercased() == "fill_space" { fills.append((result.count," ")); result.append("\0FILL") }
            else if inner.lowercased().hasPrefix("fill_space_repeat:") { let pattern = String(inner.dropFirst(18)); fills.append((result.count,pattern.isEmpty ? " " : pattern)); result.append("\0FILL") }
            else { result += markerCells(expandToken(inner)) }; pos = range.upperBound
        }
        result += markerCells(String(source[pos...])); guard !fills.isEmpty else { return result }
        let room = max(0, cols-(result.count-fills.count)), share = room/fills.count, extra = room%fills.count
        var out: [String] = []
        for (index,cell) in result.enumerated() {
            if cell != "\0FILL" { out.append(cell); continue }
            let n = fills.firstIndex { $0.0 == index }!, pattern = Array(fills[fills.firstIndex { $0.0 == index }!].1).map(String.init)
            out += (0..<(share + (n < extra ? 1 : 0))).map { pattern[$0 % pattern.count] }
        }; return out
    }
    func wrapCells(_ cells: [String], _ cols: Int) -> [[String]] {
        let words = cells.split(separator: " ").map(Array.init); var rows: [[String]] = [], current: [String] = []
        for initial in words {
            var word = initial
            while word.count > cols { if !current.isEmpty { rows.append(current); current = [] }; rows.append(Array(word.prefix(cols))); word = Array(word.dropFirst(cols)) }
            if word.isEmpty { continue }
            if !current.isEmpty, current.count+1+word.count > cols { rows.append(current); current = [] }
            current += (current.isEmpty ? [] : [" "]) + word
        }
        if !current.isEmpty || rows.isEmpty { rows.append(current) }; return rows
    }
    func dimensions(_ body: [String: Any]) -> (Int,Int) {
        switch body["device_type"] as? String ?? "flagship" {
        case "note": return (3,15)
        case "note_array": return (3*max(1,body["notes_tall"] as? Int ?? 1),15*max(1,body["notes_wide"] as? Int ?? 1))
        case "panel": return (max(1,body["grid_rows"] as? Int ?? 12),max(1,body["grid_cols"] as? Int ?? 29))
        default: return (6,22)
        }
    }
    func charsetFields(_ board: String, _ lines: [String]) -> [String: Any] {
        let charsets = ["kitchen": "vestaboard_v1", "hall": "vestaboard_v2", "desk": "vestaboard_v2", "wall": "vestaboard_v2", "tv": "vestaboard_v2", "pixoo": "led_3x5", "pixoo57": "led_5x7", "marquee": "led_5x7", "contract-board": "vestaboard_v1"]
        guard let charset = charsets[board] else { return ["charset": null, "charset_issues": null] }
        var issues: [[String: Any]] = []
        if charset.hasPrefix("vestaboard") {
            for (row,line) in lines.enumerated() { for (col,cell) in markerCells(line).enumerated() where cell.count == 1 {
                let ascii = cell.unicodeScalars.allSatisfy { $0.isASCII }
                var fallback: String?, reason = "case"
                if cell != cell.uppercased(), cell.uppercased().unicodeScalars.allSatisfy({ $0.isASCII }) { fallback = cell.uppercased() }
                else if !ascii, cell.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) { fallback = "?"; reason = "char" }
                if let fallback { issues.append(["row": row,"col": col,"token": ["type": "char","value": cell],"reason": reason,"fallback": ["type": "char","value": fallback]]) }
            } }
        }
        return ["charset": charset,"charset_issues": issues]
    }
    func toyRender(_ body: [String: Any]) -> [String: Any] {
        let (rows,cols) = dimensions(body), template = body["template"] as? [String] ?? [], metadata = body["line_metadata"] as? [Any] ?? []
        func meta(_ index: Int) -> [String: Any] { index < metadata.count ? metadata[index] as? [String: Any] ?? [:] : [:] }
        func source(_ index: Int) -> String { index < template.count ? template[index] : "" }
        func align(_ cells: [String], _ alignment: String) -> String { let clipped = Array(cells.prefix(cols)), pad = cols-clipped.count, left = alignment == "center" ? pad/2 : (alignment == "right" ? pad : 0); return (Array(repeating:" ",count:left) + clipped + Array(repeating:" ",count:pad-left)).joined() }
        var lines: [String] = [], index = 0
        while index < rows {
            let info = meta(index), alignment = info["alignment"] as? String ?? "left", cells = renderRow(source(index), cols: cols)
            if info["wrap"] as? Bool == true, cells.count > cols {
                var budget = 1
                if index+1 < rows { for later in (index+1)..<rows { if source(later).trimmingCharacters(in:.whitespaces).isEmpty || meta(later)["wrap"] as? Bool == true { budget += 1 } else { break } } }
                let pieces = wrapCells(cells,cols).prefix(budget); lines += pieces.map { align($0,alignment) }; index += pieces.count
            } else { lines.append(align(cells,alignment)); index += 1 }
        }
        var out: [String: Any] = ["rendered": lines.joined(separator:"\n"),"lines": lines,"line_count": lines.count]
        if let board = body["board_id"] as? String { out.merge(charsetFields(board,lines)) { _,new in new } }; return out
    }
    func canonical(_ body: Any) -> Data { try! JSONSerialization.data(withJSONObject: body,options:[.sortedKeys,.fragmentsAllowed]) }
    func normalized(_ body: [String: Any]) -> [String: Any] { body.filter { $0.key != "board_id" && !($0.value is NSNull) } }
    func renderCase(_ route: String, _ body: [String: Any]) -> [String: Any]? {
        let table = seed["renderCases"] as! [[String: Any]], exact = canonical(body), loose = canonical(normalized(body))
        if let match = table.first(where: { $0["route"] as? String == "/"+route && canonical($0["request"]!) == exact }) { return match["response"] as? [String: Any] }
        let candidates = table.filter { $0["route"] as? String == "/"+route && canonical(normalized($0["request"] as! [String: Any])) == loose }
        guard candidates.count == 1 else { return nil }; var result = candidates[0]["response"] as! [String: Any]
        if route == "templates/render", let board = body["board_id"] as? String, var answer = result["body"] as? [String: Any], answer["charset"] == nil { answer.merge(charsetFields(board,answer["lines"] as? [String] ?? [])) { _,new in new }; result["body"] = answer }
        return result
    }
    func renderRoute(_ method: String, _ route: String, _ body: [String: Any], _ prefix: String) -> Response? {
        guard method == "POST", ["templates/render", "templates/validate", "pages/preview/batch"].contains(route) else { return nil }
        if let hit = renderCase(route,body) { return reply(hit["status"] as? Int ?? 200,hit["body"]!) }
        if route == "templates/render" {
            guard let lines = body["template"] as? [String], !lines.isEmpty else { return reply(422,["detail":"template must be a non-empty list of strings"]) }; return reply(200,toyRender(body))
        }
        if route == "templates/validate" {
            var errors: [[String: Any]] = []
            for (line,row) in (body["template"] as? [String] ?? []).enumerated() {
                if row.components(separatedBy:"{{").count != row.components(separatedBy:"}}").count { errors.append(["line":line+1,"column":row.range(of:"{{").map { row.distance(from:row.startIndex,to:$0.lowerBound) } ?? 0,"message":"Mismatched variable braces"]); continue }
                for match in matches(#"\{\{(.*?)\}\}"#,row) {
                    let inner = substring(row,match.range(at:1)).trimmingCharacters(in:.whitespaces); if !inner.hasPrefix("=") { continue }; let expression = String(inner.dropFirst())
                    let calls = matches(#"([A-Za-z_][A-Za-z0-9_]*)\s*\("#,expression).map { substring(expression,$0.range(at:1)).uppercased() }
                    let opens = expression.filter { $0 == "(" }.count, closes = expression.filter { $0 == ")" }.count
                    if opens != closes { errors.append(["line":line+1,"column":row.distance(from:row.startIndex,to:Range(match.range,in:row)!.lowerBound),"message": opens > closes && !calls.isEmpty ? "Formula #SYNTAX: Missing ')' in call to \(calls.last!)" : "Formula #SYNTAX: Unexpected )"]); continue }
                    for name in calls where (seed["functions"] as! [String: Any])[name] == nil { errors.append(["line":line+1,"column":row.distance(from:row.startIndex,to:Range(match.range,in:row)!.lowerBound),"message":"Formula #NAME?: Unknown function: \(name)"]) }
                }
            }; return reply(200,["valid":errors.isEmpty,"errors":errors])
        }
        var previews: [String: Any] = [:], success = 0
        for id in body["page_ids"] as? [String] ?? [] {
            let page = prefix.hasPrefix("/board-") ? pages.first { $0["id"] as? String == id } : ((cases["page_get"] as! [String: Any])["id"] as? String == id ? cases["page_get"] as? [String: Any] : nil)
            guard let page else { previews[id] = ["available":false,"error":"Page not found: \(id)"]; continue }
            var request = page.filter { ["device_type","notes_wide","notes_tall","grid_rows","grid_cols"].contains($0.key) }
            if let board = body["board_id"] as? String, !board.isEmpty { request["board_id"] = board }
            let lines: [String]
            if let template = page["template"] as? [String], !template.isEmpty {
                request["template"] = template; request["line_metadata"] = page["line_metadata"] ?? null
                var exact = request; exact.removeValue(forKey:"board_id")
                if let hit = renderCase("templates/render",exact), (hit["status"] as? Int ?? 200) == 200 { lines = (hit["body"] as! [String: Any])["lines"] as! [String] } else { lines = toyRender(request)["lines"] as! [String] }
            } else if let shows = page["shows"] as? [String], !shows.isEmpty {
                request["template"] = shows.map { replaced($0,#"\{(red|orange|yellow|green|blue|violet|white|black)\}"#,"{{$1}}") }; request["line_metadata"] = shows.map { _ in ["alignment":"center","wrap":false] as [String: Any] }; lines = toyRender(request)["lines"] as! [String]
            } else { previews[id] = ["available":false,"error":"This page has no fixed grid to preview"]; continue }
            success += 1; previews[id] = ["available":true,"page_id":id,"message":lines.joined(separator:"\n"),"lines":lines,"display_type":page["device_type"] as? String ?? "flagship","raw":[String: Any]()]
        }
        return reply(200,["previews":previews,"total":previews.count,"successful":success])
    }
}
