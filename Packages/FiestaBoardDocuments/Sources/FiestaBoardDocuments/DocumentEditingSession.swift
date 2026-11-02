import Foundation

/// Value-model history, independent of UI text-selection undo. At most 100 document versions.
/// Every mutation validates a copy before adopting it, so failed edits cannot partially apply.
public struct DocumentEditingSession: Sendable {
    public private(set) var baseline: PageDocument
    public private(set) var document: PageDocument
    public private(set) var revision: UInt64 = 0
    private var savedDocument: PageDocument
    private var savedBaseline: PageDocument
    private struct Version: Sendable {
        let document: PageDocument
        let baseline: PageDocument
        let action: String
        let focus: FlexibleLocation?
        let oppositeFocus: FlexibleLocation?
    }
    public private(set) var historyFocus: FlexibleLocation?
    public var undoActionName: String? { undoHistory.last?.action }
    public var redoActionName: String? { redoHistory.last?.action }
    private func version(action: String = "Edit document", focus: FlexibleLocation? = nil, oppositeFocus: FlexibleLocation? = nil) -> Version {
        Version(document: document, baseline: baseline, action: action, focus: focus, oppositeFocus: oppositeFocus)
    }
    private var undoHistory: [Version] = []
    private var redoHistory: [Version] = []

    public init(data: Data) throws {
        let document = try PageDocument(data: data)
        self.document = document
        baseline = document
        savedDocument = document
        savedBaseline = document
    }
    public var hasUnsavedChanges: Bool { document != savedDocument || baseline != savedBaseline }
    public var canUndo: Bool { !undoHistory.isEmpty }
    public var canRedo: Bool { !redoHistory.isEmpty }

    public mutating func setName(_ name: String) throws {
        var candidate = document
        try candidate.setName(name)
        try adopt(candidate)
    }
    public mutating func replaceTemplateLine(at index: Int, with content: String) throws {
        var candidate = document
        try candidate.replaceTemplateLine(at: index, with: content)
        try adopt(candidate)
    }
    public mutating func insertTemplateLine(at index: Int, with content: String = "") throws {
        var candidate = document
        try candidate.insertTemplateLine(at: index, with: content)
        try adopt(candidate)
    }
    public mutating func removeTemplateLine(at index: Int) throws {
        var candidate = document
        try candidate.removeTemplateLine(at: index)
        try adopt(candidate)
    }
    public mutating func moveTemplateLine(from source: Int, to destination: Int) throws {
        var candidate = document
        try candidate.moveTemplateLine(from: source, to: destination)
        try adopt(candidate)
    }
    public mutating func duplicateTemplateLine(at index: Int) throws {
        var candidate = document
        try candidate.duplicateTemplateLine(at: index)
        try adopt(candidate)
    }
    /// One undo step for a burst of document typing (rows inserted, joined or edited together).
    public mutating func replaceTemplateRows(_ rows: [String], action: String = "Typing") throws {
        var candidate = document
        try candidate.replaceTemplateRows(rows)
        try adopt(candidate, action: action)
    }
    /// Plain mode's commit (rows with prefixes), one undo step like typing.
    public mutating func replacePlainRows(_ rows: [String], action: String = "Typing") throws {
        var candidate = document
        try candidate.replacePlainRows(rows)
        try adopt(candidate, action: action)
    }
    /// Board shape change (PLAN B20), one undo step.
    public mutating func setGeometry(_ geometry: PageGeometry) throws {
        var candidate = document
        try candidate.setGeometry(geometry)
        // Empty rows past the new board's last row are padding, not content: drop them in the same step.
        if var rows = candidate.editableTemplateLines {
            while rows.count > geometry.rows, rows.last?.isEmpty == true { rows.removeLast() }
            if rows.count != candidate.editableTemplateLines?.count { try candidate.replaceTemplateRows(rows) }
        }
        try adopt(candidate, action: "Change board size")
    }
    /// A legacy page's pixel canvases (PLAN B24/§2.4), one undo step per call: a whole drag,
    /// paint stroke or inspector change is committed once, when it ends.
    public mutating func setCanvases(_ canvases: [LegacyCanvas], action: String = "Edit canvases") throws {
        var candidate = document
        try candidate.setCanvases(canvases)
        try adopt(candidate, action: action)
    }
    public mutating func setLineAlignment(at index: Int, alignment: String) throws {
        var candidate = document
        try candidate.setLineAlignment(at: index, alignment: alignment)
        try adopt(candidate)
    }
    public mutating func setLineWrap(at index: Int, wrap: Bool) throws {
        var candidate = document
        try candidate.setLineWrap(at: index, wrap: wrap)
        try adopt(candidate)
    }
    public mutating func editFlexible(action: String = "Edit flexible content", focus: FlexibleLocation? = nil, undoFocus: FlexibleLocation? = nil, _ operation: (inout PageDocument) throws -> Void) throws {
        guard document.supportsFlexibleEditing else { throw FlexibleEditError.unsupported }
        var candidate = document
        try operation(&candidate)
        try adopt(candidate, action: action, focus: focus, undoFocus: undoFocus)
    }
    private mutating func adopt(_ candidate: PageDocument, action: String = "Edit document", focus: FlexibleLocation? = nil, undoFocus: FlexibleLocation? = nil) throws {
        guard candidate != document else { return }
        try advanceRevision()
        undoHistory.append(version(action: action, focus: undoFocus ?? focus, oppositeFocus: focus))
        trim(&undoHistory)
        redoHistory.removeAll()
        document = candidate
        historyFocus = focus
    }
    public mutating func undo() throws {
        guard let prior = undoHistory.last else { return }
        try advanceRevision()
        undoHistory.removeLast()
        redoHistory.append(version(action: prior.action, focus: prior.oppositeFocus, oppositeFocus: prior.focus))
        trim(&redoHistory)
        document = prior.document
        baseline = prior.baseline
        historyFocus = prior.focus
    }
    public mutating func redo() throws {
        guard let next = redoHistory.last else { return }
        try advanceRevision()
        redoHistory.removeLast()
        undoHistory.append(version(action: next.action, focus: next.oppositeFocus, oppositeFocus: next.focus))
        trim(&undoHistory)
        document = next.document
        baseline = next.baseline
        historyFocus = next.focus
    }
    /// Use the captured document that completed the write, not a newer in-flight editor value.
    public mutating func markSaved(_ document: PageDocument, baseline capturedBaseline: PageDocument? = nil) {
        savedDocument = document
        savedBaseline = capturedBaseline ?? baseline
    }

    public func snapshot(identity: DraftIdentity) throws -> DraftSnapshot {
        try DraftSnapshot(identity: identity, revision: revision,
                          baselineData: baseline.serializedData(), documentData: document.serializedData())
    }

    /// The UI must ask the user to choose recovery; a fetched server document may have changed.
    /// This restores the draft's source baseline as well as its full edited document.
    public mutating func recover(_ snapshot: DraftSnapshot) throws {
        try snapshot.validate()
        let recoveredBaseline = try PageDocument(data: snapshot.baselineData)
        let recovered = try PageDocument(data: snapshot.documentData)
        let nextRevision = max(revision, snapshot.revision)
        guard nextRevision < .max else { throw DraftError.revisionExhausted }
        undoHistory.append(version(action: "Recover local draft"))
        trim(&undoHistory)
        redoHistory.removeAll()
        revision = nextRevision + 1
        baseline = recoveredBaseline
        document = recovered
        savedDocument = recovered
        savedBaseline = recoveredBaseline
        historyFocus = nil
    }
    /// Acknowledged server storage establishes a new baseline. Old history is deliberately
    /// cleared: undo must never restore an obsolete server concurrency token.
    /// This does not mark a local draft saved; the existing disk snapshot still has its old base.
    public mutating func adoptServerDocument(_ data: Data) throws {
        let accepted = try PageDocument(data: data)
        try advanceRevision()
        document = accepted
        baseline = accepted
        undoHistory.removeAll()
        redoHistory.removeAll()
        historyFocus = nil
    }

    private mutating func advanceRevision() throws {
        guard revision < .max else { throw DraftError.revisionExhausted }
        revision += 1
    }
    private func trim(_ history: inout [Version]) {
        if history.count > 100 { history.removeFirst(history.count - 100) }
    }
}
