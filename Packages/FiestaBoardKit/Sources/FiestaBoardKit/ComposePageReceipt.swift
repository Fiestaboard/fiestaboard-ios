import Foundation
import FiestaBoardDocuments

/// Exact page storage acknowledgement. This grants no page selection, display
/// write, Schedule change, or collection-assignment permission.
public struct ComposePageReceipt: Sendable {
    public let page: Page
    public let pageData: Data
    public init(pageData: Data, name: String, request: ComposeRequest) throws {
        let page = try JSONDecoder().decode(Page.self, from: pageData)
        let fields = try RawJSONObject.members(pageData)
        let expected = request.text.components(separatedBy: "\n")
        guard PageCreationReceipt.validPage(page), page.documentProtocol == "page-document-v1", page.type == "template",
              Data(page.name.utf8) == Data(name.utf8), let template = page.template, template.count == expected.count,
              zip(template, expected).allSatisfy({ Data($0.0.utf8) == Data($0.1.utf8) }),
              let metadataData = fields["line_metadata"],
              let metadata = try? JSONDecoder().decode([ComposeBufferLine].self, from: metadataData), metadata == request.lineMetadata else { throw FiestaBoardError.unknownMutationOutcome }
        switch request.geometry {
        case .flagship:
            guard page.deviceType == "flagship", page.gridRows.map({ $0 == 6 }) ?? true,
                  page.gridCols.map({ $0 == 22 }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        case .note:
            guard page.deviceType == "note", page.gridRows.map({ $0 == 3 }) ?? true,
                  page.gridCols.map({ $0 == 15 }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        case .noteArray(let wide, let tall):
            guard page.deviceType == "note_array", page.notesWide == wide, page.notesTall == tall else { throw FiestaBoardError.unknownMutationOutcome }
        case .panel(let rows, let cols):
            guard page.deviceType == "panel", page.gridRows == rows, page.gridCols == cols else { throw FiestaBoardError.unknownMutationOutcome }
        }
        self.page = page; self.pageData = pageData
    }
}
