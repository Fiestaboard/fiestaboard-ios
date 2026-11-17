import Foundation

/// Canonical top-level destinations. Collections remains nested under Pages.
public enum ShellTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home = "Home", pages = "Pages", schedule = "Schedule", displays = "Displays", more = "More"
    public var id: Self { self }
    public var symbol: String {
        switch self {
        case .home: "house"
        case .pages: "square.grid.2x2"
        case .schedule: "calendar"
        case .displays: "rectangle.on.rectangle"
        case .more: "ellipsis"
        }
    }
}

/// Network path and actual hub reachability are separate facts. A restored path is not a successful hub read.
public struct ShellConnection: Sendable, Equatable {
    public enum Presentation: Sendable, Equatable {
        case online, offline, unreachable, connecting(still: Bool, cached: Bool)
    }
    public private(set) var reconnected = false
    private var interrupted = false
    private var hasConnected = false
    private var hubIdentity: String?
    public init() {}
    public mutating func observe(pathAvailable: Bool, hubReachable: Bool, hub: String = "") {
        if hubIdentity != hub {
            hubIdentity = hub; hasConnected = false; interrupted = false; reconnected = false
        }
        if !pathAvailable || !hubReachable { interrupted = hasConnected; reconnected = false }
        else {
            if interrupted { reconnected = true; interrupted = false }
            hasConnected = true
        }
    }
    public mutating func dismissReconnected() { reconnected = false }
    public static func presentation(pathAvailable: Bool, hubReachable: Bool, connectingSince: TimeInterval?,
                                    cachedAt: TimeInterval?, now: TimeInterval) -> Presentation {
        if !pathAvailable { return .offline }
        if let since = connectingSince {
            let cached = cachedAt.map { now >= $0 && now - $0 < 600 } ?? false
            return .connecting(still: now - since >= 5, cached: cached)
        }
        return hubReachable ? .online : .unreachable
    }
}

/// An address-scoped in-memory snapshot with a ten-minute read lifetime. No credentials or service actors enter the cache.
public struct ShellCache<Value: Sendable>: Sendable {
    private var entries: [String: (TimeInterval, Value)] = [:]
    public init() {}
    public mutating func store(_ value: Value, for hub: String, at time: TimeInterval) { entries[hub] = (time, value) }
    public func value(for hub: String, at time: TimeInterval) -> Value? {
        guard let (saved, value) = entries[hub], time >= saved, time - saved < 600 else { return nil }
        return value
    }
    public func timestamp(for hub: String) -> TimeInterval? { entries[hub]?.0 }
    public mutating func remove(for hub: String) { entries.removeValue(forKey: hub) }
}

/// Retry state outlives an individual view task when a retry re-enters Checking.
public struct ShellBackoff: Sendable {
    private var delay: Int = 2
    public init() {}
    public mutating func next() -> Int { defer { delay = min(delay * 2, 30) }; return delay }
    public mutating func reset() { delay = 2 }
}
