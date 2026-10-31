import Foundation

public struct BoardTarget: Hashable, Sendable {
    public let deployment: DeploymentURL
    public let boardID: String
    public init(deployment: DeploymentURL, boardID: String) throws {
        guard DeploymentURL.validSegment(boardID), boardID != "primary" else { throw FiestaBoardError.invalidTarget }
        self.deployment = deployment; self.boardID = boardID
    }
}
public struct AuthStatus: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let setupRequired: Bool
    public let authenticated: Bool
    public let username: String?
    public let mode: String?
    public let firstRun: Bool?
    public let sessionManagementSupported: Bool?
    public let authKind: String?
    public let tvSignIn: TVSignInStatus?
    public init(enabled: Bool, setupRequired: Bool, authenticated: Bool, username: String? = nil, mode: String? = nil, firstRun: Bool? = nil, sessionManagementSupported: Bool? = nil, authKind: String? = nil, tvSignIn: TVSignInStatus? = nil) {
        self.enabled = enabled; self.setupRequired = setupRequired; self.authenticated = authenticated
        self.username = username; self.mode = mode; self.firstRun = firstRun
        self.sessionManagementSupported = sessionManagementSupported; self.authKind = authKind; self.tvSignIn = tvSignIn
    }
    enum CodingKeys: String, CodingKey {
        case enabled, authenticated, username, mode
        case sessionManagementSupported = "session_management_supported", authKind = "auth_kind", tvSignIn = "tv_sign_in"
        case setupRequired = "setup_required", firstRun = "first_run"
    }
}
public struct VersionInfo: Codable, Sendable, Equatable {
    public let packageVersion: String
    public let buildVersion: String
    public let runningVersion: String?
    public let isDev: Bool
    public var displayedVersion: String { runningVersion ?? packageVersion }
    enum CodingKeys: String, CodingKey {
        case packageVersion = "package_version", buildVersion = "build_version"
        case runningVersion = "running_version", isDev = "is_dev"
    }
}
public enum DraftAccess: String, Codable, Sendable { case readOnly, candidateWrites, simulated }
public struct ConnectionStatus: Codable, Sendable {
    public let version: VersionInfo
    public let access: DraftAccess
    public let isDemo: Bool
    public let sessionPersistence: String
}
public struct BoardSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let deviceType: String
    public let rows: Int
    public let cols: Int
    public let isPrimary: Bool
    public let paused: Bool
    public let scheduleEnabled: Bool
    public let autoRestore: Bool?
    public let output: String
    public let deviceModel: String?
    public let charset: String?
    enum CodingKeys: String, CodingKey {
        case id, name, rows, cols, paused, output, charset
        case deviceType = "device_type", isPrimary = "is_primary", scheduleEnabled = "schedule_enabled"
        case autoRestore = "auto_restore", deviceModel = "device_model"
    }
    func validate() throws {
        guard DeploymentURL.validSegment(id), id != "primary", !name.isEmpty,
              rows > 0, cols > 0, rows <= 2048, cols <= 2048, rows * cols <= 1_048_576 else {
            throw FiestaBoardError.invalidResponse
        }
    }
}
public struct CanvasLayer: Codable, Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let rgba: String
}
public enum RenderingSupport: String, Codable, Sendable { case flapGrid, unsupported }
/// Server-reported content, which may be cached. It is not independent proof of physical output.
public struct BoardDetail: Codable, Sendable {
    public let summary: BoardSummary
    public let characters: [[Int]]?
    public let expectedCharacters: [[Int]]?
    public let text: String?
    public let readAt: String?
    public let activePageID: String?
    public let scheduledPageID: String?
    public let resolvedPageID: String?
    public let source: String
    public let defaultPageID: String?
    public let layers: [CanvasLayer]?
    public var renderingSupport: RenderingSupport {
        guard summary.charset == "vestaboard_v1", layers?.isEmpty != false,
              (try? validate()) != nil,
              (characters ?? []).joined().allSatisfy({ (0...71).contains($0) }) else { return .unsupported }
        return .flapGrid
    }
    enum CodingKeys: String, CodingKey {
        case characters, text, source, layers
        case defaultPageID = "default_page_id"
        case expectedCharacters = "expected_characters", readAt = "read_at", activePageID = "active_page_id"
        case scheduledPageID = "scheduled_page_id", resolvedPageID = "resolved_page_id"
    }
    public init(from decoder: any Decoder) throws {
        summary = try BoardSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characters = try c.decodeIfPresent([[Int]].self, forKey: .characters)
        expectedCharacters = try c.decodeIfPresent([[Int]].self, forKey: .expectedCharacters)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
        activePageID = try c.decodeIfPresent(String.self, forKey: .activePageID)
        scheduledPageID = try c.decodeIfPresent(String.self, forKey: .scheduledPageID)
        resolvedPageID = try c.decodeIfPresent(String.self, forKey: .resolvedPageID)
        defaultPageID = try c.decodeIfPresent(String.self, forKey: .defaultPageID)
        source = try c.decode(String.self, forKey: .source)
        layers = try c.decodeIfPresent([CanvasLayer].self, forKey: .layers)
    }
    public func encode(to encoder: any Encoder) throws {
        try summary.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(characters, forKey: .characters)
        try c.encodeIfPresent(expectedCharacters, forKey: .expectedCharacters)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(readAt, forKey: .readAt)
        try c.encodeIfPresent(activePageID, forKey: .activePageID)
        try c.encodeIfPresent(scheduledPageID, forKey: .scheduledPageID)
        try c.encodeIfPresent(resolvedPageID, forKey: .resolvedPageID)
        try c.encodeIfPresent(defaultPageID, forKey: .defaultPageID)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(layers, forKey: .layers)
    }
    func validate() throws {
        try summary.validate()
        for grid in [characters, expectedCharacters].compactMap({ $0 }) {
            guard grid.count == summary.rows, grid.allSatisfy({ $0.count == summary.cols }) else {
                throw FiestaBoardError.invalidResponse
            }
        }
        guard ["manual", "schedule", "none"].contains(source) else { throw FiestaBoardError.invalidResponse }
    }
}
/// A read projection. Editing retains the original raw document separately.
public struct Page: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: String
    /// Flexible and future document families may have no fixed character grid.
    /// This read projection must not make one such page invalidate the library.
    public let deviceType: String?
    public let template: [String]?
    public let revision: String?
    public let editProtocol: String?
    public let documentProtocol: String?
    public let supportsTemplateEditing: Bool
    public let notesWide: Int?
    public let notesTall: Int?
    public let gridRows: Int?
    public let gridCols: Int?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        // Unsupported families retain their full raw document elsewhere. Their
        // projection fields must not invalidate the rest of a mixed library.
        documentProtocol = try? c.decode(String.self, forKey: .documentProtocol)
        // Older audited template documents omit this field. A present unknown,
        // null or malformed protocol never inherits that legacy permission.
        supportsTemplateEditing = type == "template" && (!c.contains(.documentProtocol) || documentProtocol == "page-document-v1")
        let legacy = supportsTemplateEditing
        deviceType = legacy ? try c.decode(String.self, forKey: .deviceType) : try? c.decodeIfPresent(String.self, forKey: .deviceType)
        template = legacy ? try c.decodeIfPresent([String].self, forKey: .template) : try? c.decodeIfPresent([String].self, forKey: .template)
        revision = legacy ? try c.decodeIfPresent(String.self, forKey: .revision) : try? c.decodeIfPresent(String.self, forKey: .revision)
        editProtocol = legacy ? try c.decodeIfPresent(String.self, forKey: .editProtocol) : try? c.decodeIfPresent(String.self, forKey: .editProtocol)
        notesWide = legacy ? try c.decodeIfPresent(Int.self, forKey: .notesWide) : try? c.decodeIfPresent(Int.self, forKey: .notesWide)
        notesTall = legacy ? try c.decodeIfPresent(Int.self, forKey: .notesTall) : try? c.decodeIfPresent(Int.self, forKey: .notesTall)
        gridRows = legacy ? try c.decodeIfPresent(Int.self, forKey: .gridRows) : try? c.decodeIfPresent(Int.self, forKey: .gridRows)
        gridCols = legacy ? try c.decodeIfPresent(Int.self, forKey: .gridCols) : try? c.decodeIfPresent(Int.self, forKey: .gridCols)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, type, template, revision
        case editProtocol = "edit_protocol", documentProtocol = "document_protocol"
        case deviceType = "device_type", notesWide = "notes_wide", notesTall = "notes_tall"
        case gridRows = "grid_rows", gridCols = "grid_cols"
    }
}
public enum MutationDisposition: String, Codable, Sendable { case accepted, held, notSent, selectionStored }
/// An accepted send is not proof that hardware physically changed.
public struct MutationResult: Codable, Sendable {
    public let boardID: String
    public let pageID: String?
    public let disposition: MutationDisposition
    public let sent: Bool
    public let silenced: Bool
    public let deliveryFailed: Bool
    public let warningCount: Int
}
