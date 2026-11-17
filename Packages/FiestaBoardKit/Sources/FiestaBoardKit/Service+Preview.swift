import Foundation

/// One page's entry in `POST /pages/preview/batch` (S:src/pages/models.py:463-514):
/// either the rendered page or a per-page error.
public struct PagePreview: Sendable, Equatable {
    public let pageID: String
    public let available: Bool
    /// Rendered lines (markup: `{63}` colour markers) — the flap thumbnail.
    public let lines: [String]
    public let displayType: String?
    /// Rich cells (only for a rich-charset/LED `board_id`), raw JSON objects.
    public let cellsJSON: Data?
    public let layers: [CanvasLayer]
    public let error: String?
    public init(pageID: String, available: Bool, lines: [String], displayType: String?, cellsJSON: Data?,
                layers: [CanvasLayer], error: String?) {
        self.pageID = pageID; self.available = available; self.lines = lines; self.displayType = displayType
        self.cellsJSON = cellsJSON; self.layers = layers; self.error = error
    }
}

/// Page thumbnails (B11). A read: no page is written and nothing is sent.
public protocol PagePreviewReading: Sendable {
    func previewBatch(pageIDs: [String], boardID: String?) async throws -> [String: PagePreview]
}

extension LiveFiestaBoardService: PagePreviewReading {
    public func previewBatch(pageIDs: [String], boardID: String?) async throws -> [String: PagePreview] {
        guard pageIDs.allSatisfy({ DeploymentURL.validSegment($0) }),
              boardID.map(DeploymentURL.validSegment) ?? true else { throw FiestaBoardError.invalidTarget }
        var body: [String: Any] = ["page_ids": pageIDs]
        if let boardID { body["board_id"] = boardID }
        let batch: Batch = try await fetch(APIRequest(.post, path: ["pages", "preview", "batch"],
                                                      body: JSONSerialization.data(withJSONObject: body), cachePolicy: .noStore))
        return batch.previews
    }
}

public extension PagePreview {
    /// Decodes the batch envelope loosely: a malformed entry becomes an error
    /// entry, never a failed batch.
    static func decodeBatch(_ data: Data) throws -> [String: PagePreview] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let previews = root["previews"] as? [String: Any] else { throw FiestaBoardError.invalidResponse }
        var out: [String: PagePreview] = [:]
        for (id, value) in previews {
            guard let entry = value as? [String: Any] else { continue }
            let available = entry["available"] as? Bool ?? false
            let layers: [CanvasLayer] = (entry["layers"] as? [Any]).flatMap {
                try? JSONDecoder().decode([CanvasLayer].self, from: JSONSerialization.data(withJSONObject: $0))
            } ?? []
            let cells = (entry["cells"] as? [Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            out[id] = PagePreview(pageID: id, available: available,
                                  lines: (entry["lines"] as? [Any])?.compactMap { $0 as? String } ?? [],
                                  displayType: entry["display_type"] as? String, cellsJSON: cells, layers: layers,
                                  error: available ? nil : (entry["error"] as? String ?? "Preview unavailable"))
        }
        return out
    }
}

/// `fetch` decodes a `Decodable`; this one keeps the loose decoder above.
private struct Batch: Decodable, Sendable {
    let previews: [String: PagePreview]
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(LooseJSON.self)
        previews = try PagePreview.decodeBatch(JSONSerialization.data(withJSONObject: value.object))
    }
}
private struct LooseJSON: Decodable {
    let object: Any
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { object = NSNull() }
        else if let v = try? c.decode(Bool.self) { object = v }
        else if let v = try? c.decode(Int.self) { object = v }
        else if let v = try? c.decode(Double.self) { object = v }
        else if let v = try? c.decode(String.self) { object = v }
        else if let v = try? c.decode([LooseJSON].self) { object = v.map(\.object) }
        else { object = try c.decode([String: LooseJSON].self).mapValues(\.object) }
    }
}
