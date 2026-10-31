import Foundation

public enum CollectionSelectionMode: String, CaseIterable, Codable, Sendable { case time, variable, random }

public struct CollectionIntervalConfig: Codable, Sendable, Equatable {
    public var intervalSeconds: Int
    public init(intervalSeconds: Int = 30) { self.intervalSeconds = intervalSeconds }
    enum CodingKeys: String, CodingKey { case intervalSeconds = "interval_seconds" }
}
public struct CollectionRule: Codable, Sendable, Equatable {
    public var expression: String
    public var pageID: String
    public init(expression: String, pageID: String) { self.expression = expression; self.pageID = pageID }
    enum CodingKeys: String, CodingKey { case expression; case pageID = "page_id" }
}
public struct CollectionVariableConfig: Codable, Sendable, Equatable {
    public var rules: [CollectionRule]
    public var defaultPageID: String
    public var pollSeconds: Int
    public init(rules: [CollectionRule] = [], defaultPageID: String, pollSeconds: Int = 10) {
        self.rules = rules; self.defaultPageID = defaultPageID; self.pollSeconds = pollSeconds
    }
    enum CodingKeys: String, CodingKey { case rules; case defaultPageID = "default_page_id"; case pollSeconds = "poll_seconds" }
}

/// The supported collection fields. Optional configs deliberately encode null to clear old modes.
public struct CollectionInput: Codable, Sendable, Equatable {
    public var name: String
    public var pageIDs: [String]
    public var selectionMode: CollectionSelectionMode
    public var time: CollectionIntervalConfig
    public var variable: CollectionVariableConfig?
    public var random: CollectionIntervalConfig?
    public init(name: String, pageIDs: [String], selectionMode: CollectionSelectionMode = .time,
                time: CollectionIntervalConfig = .init(), variable: CollectionVariableConfig? = nil,
                random: CollectionIntervalConfig? = nil) {
        self.name = name; self.pageIDs = pageIDs; self.selectionMode = selectionMode
        self.time = time; self.variable = variable; self.random = random
    }
    enum CodingKeys: String, CodingKey { case name, time, variable, random; case pageIDs = "page_ids"; case selectionMode = "selection_mode" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(pageIDs, forKey: .pageIDs)
        try c.encode(selectionMode, forKey: .selectionMode); try c.encode(time, forKey: .time)
        try c.encode(variable, forKey: .variable); try c.encode(random, forKey: .random)
    }
    public func validate() throws {
        guard (1...100).contains(name.unicodeScalars.count), !pageIDs.isEmpty,
              Set(pageIDs).count == pageIDs.count,
              pageIDs.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("collection:") }),
              (5...86400).contains(time.intervalSeconds),
              random.map({ (5...86400).contains($0.intervalSeconds) }) ?? true,
              selectionMode != .random || random != nil,
              selectionMode != .variable || variable != nil else { throw FiestaBoardError.collectionWritesDisabled }
        if let variable {
            guard (2...600).contains(variable.pollSeconds), pageIDs.contains(variable.defaultPageID),
                  variable.rules.allSatisfy({ !$0.expression.isEmpty && pageIDs.contains($0.pageID) }) else {
                throw FiestaBoardError.collectionWritesDisabled
            }
        }
    }
}

public struct PageCollection: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let pageIDs: [String]
    /// Kept as a string so future modes remain readable.
    public let selectionMode: String
    public let time: CollectionIntervalConfig
    public let variable: CollectionVariableConfig?
    public let random: CollectionIntervalConfig?
    public let revision: String?
    public let editProtocol: String?
    public let createdAt: String?
    public let updatedAt: String?
    private var containsUnknownFields = false

    public init(id: String, name: String, pageIDs: [String], selectionMode: String = "time",
                time: CollectionIntervalConfig = .init(), variable: CollectionVariableConfig? = nil,
                random: CollectionIntervalConfig? = nil, revision: String? = nil, editProtocol: String? = nil,
                createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id; self.name = name; self.pageIDs = pageIDs; self.selectionMode = selectionMode
        self.time = time; self.variable = variable; self.random = random; self.revision = revision
        self.editProtocol = editProtocol; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    public var supportsEditing: Bool {
        guard !containsUnknownFields, let mode = CollectionSelectionMode(rawValue: selectionMode) else { return false }
        return (try? CollectionInput(name: name, pageIDs: pageIDs, selectionMode: mode, time: time, variable: variable, random: random).validate()) != nil
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, time, variable, random, revision
        case pageIDs = "page_ids", selectionMode = "selection_mode", editProtocol = "edit_protocol"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        pageIDs = try c.decode([String].self, forKey: .pageIDs); selectionMode = try c.decode(String.self, forKey: .selectionMode)
        time = try c.decode(CollectionIntervalConfig.self, forKey: .time)
        variable = try c.decodeIfPresent(CollectionVariableConfig.self, forKey: .variable)
        random = try c.decodeIfPresent(CollectionIntervalConfig.self, forKey: .random)
        revision = try c.decodeIfPresent(String.self, forKey: .revision); editProtocol = try c.decodeIfPresent(String.self, forKey: .editProtocol)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt); updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        containsUnknownFields = try CollectionFields.hasUnknownFields(decoder)
    }
}

private struct CollectionFields: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    static func hasUnknownFields(_ decoder: any Decoder) throws -> Bool {
        let c = try decoder.container(keyedBy: Self.self)
        guard Set(c.allKeys.map(\.stringValue)).isSubset(of: Set(PageCollection.CodingKeys.allCases.map(\.rawValue))) else { return true }
        for (field, allowed) in [("time", Set(["interval_seconds"])), ("random", Set(["interval_seconds"])), ("variable", Set(["rules", "default_page_id", "poll_seconds"]))] {
            let key = Self(stringValue: field)!
            if c.contains(key), try !c.decodeNil(forKey: key) {
                let nested = try c.nestedContainer(keyedBy: Self.self, forKey: key)
                if !Set(nested.allKeys.map(\.stringValue)).isSubset(of: allowed) { return true }
                if field == "variable", let rules = Self(stringValue: "rules"), nested.contains(rules) {
                    var array = try nested.nestedUnkeyedContainer(forKey: rules)
                    while !array.isAtEnd {
                        let rule = try array.nestedContainer(keyedBy: Self.self)
                        if !Set(rule.allKeys.map(\.stringValue)).isSubset(of: ["expression", "page_id"]) { return true }
                    }
                }
            }
        }
        return false
    }
}

public struct CollectionWriteAccess: Codable, Sendable, Equatable {
    public let writesOptedIn: Bool
    public let canCreate: Bool
    public let isSimulated: Bool
    public init(writesOptedIn: Bool, canCreate: Bool, isSimulated: Bool) {
        self.writesOptedIn = writesOptedIn; self.canCreate = canCreate; self.isSimulated = isSimulated
    }
}

extension FiestaBoardService {
    public func scopedCollectionDocument(id: String?) async throws -> ScopedCollectionDocument { throw FiestaBoardError.staleSession }
    public func collectionAccess() async -> CollectionWriteAccess { .init(writesOptedIn: false, canCreate: false, isSimulated: isDemo) }
    public func collections() async throws -> [PageCollection] { throw FiestaBoardError.collectionWritesDisabled }
    public func collection(id: String) async throws -> PageCollection { throw FiestaBoardError.collectionWritesDisabled }
    public func acknowledgeCollectionCreationReview() async throws { throw FiestaBoardError.collectionWritesDisabled }
    public func createCollection(_ input: CollectionInput) async throws -> PageCollection { throw FiestaBoardError.collectionWritesDisabled }
    public func updateCollection(id: String, input: CollectionInput, expectedRevision: String) async throws -> PageCollection { throw FiestaBoardError.collectionWritesDisabled }
    public func deleteCollection(id: String, expectedRevision: String) async throws { throw FiestaBoardError.collectionWritesDisabled }
}
