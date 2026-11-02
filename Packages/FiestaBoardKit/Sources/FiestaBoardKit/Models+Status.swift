import Foundation

/// One `/settings/board` `boards[]` entry, kept as its raw JSON: a stored
/// `BoardInstance` dict whose appearance fields are all optional and are read
/// by the renderer's `DisplayModel`. Internal route; no compatibility promise.
public struct StoredBoardEntry: Sendable, Equatable {
    public let id: String
    public let json: Data
    public func dictionary() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    }
    public init(id: String, json: Data) { self.id = id; self.json = json }

    /// Decodes `{"boards": [ {...}, ... ]}`; entries without an id are skipped.
    public static func decodeList(_ data: Data) throws -> [StoredBoardEntry] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let boards = object["boards"] as? [[String: Any]] else { throw FiestaBoardError.invalidResponse }
        return boards.compactMap { board in
            guard let id = board["id"] as? String, let json = try? JSONSerialization.data(withJSONObject: board) else { return nil }
            return StoredBoardEntry(id: id, json: json)
        }
    }
}

/// `/v1/status` `boards[id]` (S:src/service_api/models.py:43-72).
public struct BoardRuntimeStatus: Codable, Sendable, Equatable {
    public struct OutputStatus: Codable, Sendable, Equatable {
        public let state: String
        public let message: String?
    }
    public let configured: Bool?
    public let paused: Bool?
    public let activePageID: String?
    public let error: String?
    public let outputStatus: OutputStatus?
    enum CodingKeys: String, CodingKey {
        case configured, paused, error
        case activePageID = "active_page_id", outputStatus = "output_status"
    }
}
public struct ServiceStatusReport: Codable, Sendable, Equatable {
    public let running: Bool?
    public let boards: [String: BoardRuntimeStatus]
}

/// `/schedules/active/page` and `/settings/active-page` (the latter has no
/// `schedule_enabled` / `temporary_override`).
public struct ActivePageStatus: Codable, Sendable, Equatable {
    public struct TemporaryOverride: Codable, Sendable, Equatable {
        public let active: Bool
        public let pageID: String?
        public let remainingSeconds: Double?
        public let expiresAt: String?
        enum CodingKeys: String, CodingKey {
            case active, pageID = "page_id", remainingSeconds = "remaining_seconds", expiresAt = "expires_at"
        }
        public init(active: Bool, pageID: String? = nil, remainingSeconds: Double? = nil, expiresAt: String? = nil) {
            self.active = active; self.pageID = pageID; self.remainingSeconds = remainingSeconds; self.expiresAt = expiresAt
        }
    }
    public let pageID: String?
    public let resolvedPageID: String?
    public let resolvedNextCheckSeconds: Double?
    public let scheduleEnabled: Bool?
    public let temporaryOverride: TemporaryOverride?
    enum CodingKeys: String, CodingKey {
        case pageID = "page_id", resolvedPageID = "resolved_page_id"
        case resolvedNextCheckSeconds = "resolved_next_check_seconds", scheduleEnabled = "schedule_enabled"
        case temporaryOverride = "temporary_override"
    }
    public init(pageID: String?, resolvedPageID: String? = nil, resolvedNextCheckSeconds: Double? = nil,
                scheduleEnabled: Bool? = nil, temporaryOverride: TemporaryOverride? = nil) {
        self.pageID = pageID; self.resolvedPageID = resolvedPageID; self.resolvedNextCheckSeconds = resolvedNextCheckSeconds
        self.scheduleEnabled = scheduleEnabled; self.temporaryOverride = temporaryOverride
    }
}

/// `/silence-status` (S:src/service_api/models.py:109-146).
public struct SilenceStatus: Codable, Sendable, Equatable {
    public let enabled: Bool?
    public let active: Bool
    public let mode: String?
    public let pageID: String?
    public let endsAtUTC: String?
    enum CodingKeys: String, CodingKey {
        case enabled, active, mode, pageID = "page_id", endsAtUTC = "ends_at_utc"
    }
    public init(enabled: Bool? = nil, active: Bool, mode: String? = nil, pageID: String? = nil, endsAtUTC: String? = nil) {
        self.enabled = enabled; self.active = active; self.mode = mode; self.pageID = pageID; self.endsAtUTC = endsAtUTC
    }
}

/// `/settings/display` (global).
public struct BoardDisplaySettings: Codable, Sendable, Equatable {
    public let reduceMotion: Bool?
    public let boardAnimations: Bool?
    public let boardFlapSpeed: String?
    enum CodingKeys: String, CodingKey {
        case reduceMotion = "reduce_motion", boardAnimations = "board_animations", boardFlapSpeed = "board_flap_speed"
    }
    public init(reduceMotion: Bool? = nil, boardAnimations: Bool? = nil, boardFlapSpeed: String? = nil) {
        self.reduceMotion = reduceMotion; self.boardAnimations = boardAnimations; self.boardFlapSpeed = boardFlapSpeed
    }
    /// FiestaUI flap speed presets, clamped 8…2000 ms.
    public var flapStepMs: Int {
        switch boardFlapSpeed { case "hardware": 16; case "quick": 48; case "relaxed": 130; default: 80 }
    }
}

/// `/board/current-message` (deprecated, still served).
public struct CurrentBoardMessage: Codable, Sendable, Equatable {
    public let characters: [[Int]]?
    public let message: String?
    public let rows: Int?
    public let cols: Int?
    public let expectedCharacters: [[Int]]?
    public let cachedAt: String?
    public let layers: [CanvasLayer]?
    public let externalCharacters: [[Int]]?
    public let overwrittenAt: String?
    enum CodingKeys: String, CodingKey {
        case characters, message, rows, cols, layers
        case expectedCharacters = "expected_characters", cachedAt = "cached_at"
        case externalCharacters = "external_characters", overwrittenAt = "overwritten_at"
    }
}
