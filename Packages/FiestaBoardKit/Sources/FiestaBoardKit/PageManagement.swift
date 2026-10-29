import Foundation

/// This bounded adapter creates template pages only. Panel geometry is always explicit.
public enum PageCreationFamily: Sendable, Equatable {
    case flagship
    case panel(rows: Int, cols: Int)
}
public struct PageCreationInput: Encodable, Sendable, Equatable {
    public let name: String
    public let family: PageCreationFamily
    public let template: [String]
    public init(name: String, family: PageCreationFamily, template: [String] = []) {
        self.name = name; self.family = family; self.template = template
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FiestaBoardError.invalidRequestContext }
        if case .panel(let rows, let cols) = family {
            guard rows > 0, cols > 0 else { throw FiestaBoardError.invalidRequestContext }
        }
    }
    enum CodingKeys: String, CodingKey { case name, type, template, deviceType = "device_type", rows = "grid_rows", cols = "grid_cols" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode("template", forKey: .type); try c.encode(template, forKey: .template)
        switch family {
        case .flagship: try c.encode("flagship", forKey: .deviceType)
        case .panel(let rows, let cols):
            try c.encode("panel", forKey: .deviceType); try c.encode(rows, forKey: .rows); try c.encode(cols, forKey: .cols)
        }
    }
}
public struct PageManagementCapability: Sendable, Equatable {
    public let canCreate: Bool
    public let canDelete: Bool
    public let isSimulated: Bool
    public init(canCreate: Bool, canDelete: Bool, isSimulated: Bool = false) {
        self.canCreate = canCreate; self.canDelete = canDelete; self.isSimulated = isSimulated
    }
}
/// A single dispatch intent, issued by one service session. Retain consumed drafts across sheet reopen.
public struct PageCreationContext: Sendable, Equatable {
    public let deployment: DeploymentURL
    public let input: PageCreationInput
    let generation: UInt64
    let token: UUID
}
/// The original full page bytes and revision shown for confirmation, scoped to one service session.
public struct PageDeletionContext: Sendable, Equatable {
    public let deployment: DeploymentURL
    public let page: Page
    public let pageData: Data
    let generation: UInt64
    let token: UUID
}
public struct PageCreationReceipt: Sendable {
    public let page: Page
    /// Exact full author document, including rich/unknown fields. Never rebuild from `page`.
    public let pageData: Data
    public init(pageData: Data, input: PageCreationInput) throws {
        guard let fields = try? RawJSONObject.members(pageData),
              let page = try? JSONDecoder().decode(Page.self, from: pageData),
              Self.validPage(page), page.name == input.name, page.type == "template", page.template == input.template,
              fields["document_protocol"].flatMap({ try? JSONDecoder().decode(String.self, from: $0) }) == "page-document-v1" else { throw FiestaBoardError.unknownMutationOutcome }
        switch input.family {
        case .flagship:
            guard page.deviceType == "flagship", page.gridRows.map({ $0 == 6 }) ?? true,
                  page.gridCols.map({ $0 == 22 }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        case .panel(let rows, let cols):
            guard page.deviceType == "panel", page.gridRows == rows, page.gridCols == cols else { throw FiestaBoardError.unknownMutationOutcome }
        }
        self.page = page; self.pageData = pageData
    }
    static func validPage(_ page: Page) -> Bool {
        DeploymentURL.validSegment(page.id) && page.editProtocol == "page-revision-v1" &&
        page.revision.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 256 }) == true
    }
}
/// Storage acknowledgement only. Refresh library and boards to inspect all replacement references.
public struct PageDeletionReceipt: Sendable {
    public let id: String
    public let defaultPageCreated: Bool
    public let newPageID: String?
    public let activePageUpdated: Bool
    public let newActivePageID: String?
    public init(rawData: Data, expectedPageID: String) throws {
        struct Reply: Decodable {
            let id: String; let message: String; let default_page_created: Bool; let new_page_id: String?
            let active_page_updated: Bool; let new_active_page_id: String?
        }
        guard let fields = try? RawJSONObject.members(rawData), fields["new_page_id"] != nil, fields["new_active_page_id"] != nil,
              let r = try? JSONDecoder().decode(Reply.self, from: rawData), r.id == expectedPageID,
              r.default_page_created == (r.new_page_id != nil), r.active_page_updated == (r.new_active_page_id != nil),
              r.new_page_id.map({ DeploymentURL.validSegment($0) && $0 != expectedPageID }) ?? true,
              r.new_active_page_id.map({ DeploymentURL.validSegment($0) && $0 != expectedPageID }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        id = r.id; defaultPageCreated = r.default_page_created; newPageID = r.new_page_id
        activePageUpdated = r.active_page_updated; newActivePageID = r.new_active_page_id
    }
}
public extension FiestaBoardService {
    func pageManagementCapability() async -> PageManagementCapability { .init(canCreate: false, canDelete: false) }
    func preparePageCreation(_ input: PageCreationInput) async throws -> PageCreationContext { throw FiestaBoardError.pageWritesDisabled }
    func createPage(context: PageCreationContext) async throws -> PageCreationReceipt { throw FiestaBoardError.pageWritesDisabled }
    func readPageForDeletion(id: String) async throws -> PageDeletionContext { throw FiestaBoardError.pageWritesDisabled }
    func deletePage(context: PageDeletionContext) async throws -> PageDeletionReceipt { throw FiestaBoardError.pageWritesDisabled }
}
