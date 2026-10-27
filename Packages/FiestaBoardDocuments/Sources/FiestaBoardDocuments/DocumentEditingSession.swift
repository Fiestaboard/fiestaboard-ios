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
    }
    private var version: Version { Version(document: document, baseline: baseline) }
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
    private mutating func adopt(_ candidate: PageDocument) throws {
        guard candidate != document else { return }
        try advanceRevision()
        undoHistory.append(version)
        trim(&undoHistory)
        redoHistory.removeAll()
        document = candidate
    }
    public mutating func undo() throws {
        guard let prior = undoHistory.last else { return }
        try advanceRevision()
        undoHistory.removeLast()
        redoHistory.append(version)
        trim(&redoHistory)
        document = prior.document
        baseline = prior.baseline
    }
    public mutating func redo() throws {
        guard let next = redoHistory.last else { return }
        try advanceRevision()
        redoHistory.removeLast()
        undoHistory.append(version)
        trim(&undoHistory)
        document = next.document
        baseline = next.baseline
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
        undoHistory.append(version)
        trim(&undoHistory)
        redoHistory.removeAll()
        revision = nextRevision + 1
        baseline = recoveredBaseline
        document = recovered
        savedDocument = recovered
        savedBaseline = recoveredBaseline
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
    }

    private mutating func advanceRevision() throws {
        guard revision < .max else { throw DraftError.revisionExhausted }
        revision += 1
    }
    private func trim(_ history: inout [Version]) {
        if history.count > 100 { history.removeFirst(history.count - 100) }
    }
}
