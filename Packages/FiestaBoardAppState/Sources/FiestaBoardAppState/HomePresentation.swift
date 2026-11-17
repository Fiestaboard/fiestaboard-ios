import Foundation
import FiestaBoardKit

/// Clock-driven presentation uses the hub's instants, never a local schedule resolver.
public enum HomeTiming {
    public static func instant(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
    /// The write API accepts whole minutes; keep that granularity explicit.
    public static func durationMinutes(until end: Date, now: Date) -> Int? {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0, seconds <= 28800 else { return nil }
        return Int(ceil(seconds / 60))
    }
    public static func remainingLabel(expiresAt: String?, now: Date) -> String {
        guard expiresAt != nil else { return "Until canceled" }
        guard let end = instant(expiresAt) else { return "" }
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return "Ending…" }
        guard seconds >= 60 else { return "<1m left" }
        let minutes = Int(ceil(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }
}

public enum HomeBanner: String, Equatable, Sendable {
    case displayOffline, paused, silenced
    public var title: String {
        switch self {
        case .displayOffline: "Display offline"
        case .paused: "Paused"
        case .silenced: "Silenced"
        }
    }
}
public struct HomeNextChange: Equatable, Sendable {
    public let at: Date
    public let title: String
    public let pageName: String?
}
public struct HomePresentation: Equatable, Sendable {
    public let modeLabel: String
    public let overrideRemaining: String?
    /// Only an active, ordered interval can describe expiry/progress truthfully.
    public let overrideExpiresAt: Date?
    public let overrideRemainingFraction: Double?
    public let overrideResumesSchedule: Bool
    public let banner: HomeBanner?
    public let nextChange: HomeNextChange?

    public static func make(detail: BoardDetail?, showing: NowShowing?, silence: SilenceStatus?,
                            pageNames: [String: String], now: Date) -> HomePresentation {
        let activeOverride: Bool
        if case .override = showing?.mode { activeOverride = true }
        else { activeOverride = detail?.overrideStartedAt != nil }
        let mode: String
        if detail?.summary.paused == true { mode = "Paused" }
        else if activeOverride { mode = "Override" }
        else if silence?.active == true { mode = "Silenced" }
        else if showing?.collection == true { mode = "Collection" }
        else if showing?.mode == .schedule || detail?.summary.scheduleEnabled == true { mode = "Schedule Mode" }
        else { mode = "Manual Mode" }
        let banner: HomeBanner?
        if detail?.health?.reachable == false { banner = .displayOffline }
        else if detail?.summary.paused == true { banner = .paused }
        else if silence?.active == true && !activeOverride { banner = .silenced }
        else { banner = nil }
        var next: HomeNextChange?
        if let at = HomeTiming.instant(detail?.nextChangeAt), at > now {
            let title: String
            switch detail?.nextChangeReason {
            case "override_ends": title = "Override ends"
            case "silence_starts": title = "Silence Schedule starts"
            case "silence_ends": title = "Silence Schedule ends"
            case "collection": title = "Collection may change"
            case "schedule": title = detail?.nextPageID.flatMap { pageNames[$0] } ?? "Schedule changes"
            default: title = "Next change"
            }
            next = HomeNextChange(at: at, title: title, pageName: detail?.nextPageID.flatMap { pageNames[$0] })
        }
        var expiry: Date?
        var fraction: Double?
        if activeOverride, let start = HomeTiming.instant(detail?.overrideStartedAt),
           let end = HomeTiming.instant(detail?.overrideExpiresAt) {
            let duration = end.timeIntervalSince(start)
            let remaining = end.timeIntervalSince(now)
            if duration.isFinite, remaining.isFinite, duration > 0, start <= now, remaining > 0 {
                expiry = end
                fraction = min(1, max(0, remaining / duration))
            }
        }
        return HomePresentation(modeLabel: mode,
            overrideRemaining: activeOverride ? HomeTiming.remainingLabel(expiresAt: detail?.overrideExpiresAt, now: now) : nil,
            overrideExpiresAt: expiry, overrideRemainingFraction: fraction,
            overrideResumesSchedule: expiry != nil && detail?.summary.scheduleEnabled == true
                && detail?.summary.paused == false && silence?.active != true,
            banner: banner, nextChange: next)
    }
}

public enum HomeControlOutcome: Hashable, Sendable {
    case pageSelected, overrideCanceled, overrideRestored, displayResumed, unconfirmed, readbackRequired, signInRequired, failed
    public var message: String {
        switch self {
        case .displayResumed: "Display resumed"
        case .pageSelected: "Page selected"
        case .overrideCanceled: "Override canceled"
        case .overrideRestored: "Override restored"
        case .readbackRequired: "The change was accepted. Refresh the display before another action."
        case .unconfirmed: "The result couldn't be confirmed. Refresh before trying again."
        case .signInRequired: "Sign in again to control this display."
        case .failed: "Couldn't read the display. Refresh and try again."
        }
    }
}

/// A single server-reported intent. Never infer a queue or a writable action.
public struct HomeSilencePresentation: Equatable, Sendable {
    public let endsAt: Date?
    public let holdsBlockedSends: Bool
    public let heldPreview: String?
    public let queuedAt: Date?
    public static func make(status: SilenceStatus?, boardID: String) -> Self? {
        guard let status, status.active, status.boardID == nil || status.boardID == boardID else { return nil }
        return Self(endsAt: HomeTiming.instant(status.endsAtUTC), holdsBlockedSends: status.holdsBlockedSends,
            heldPreview: status.held?.preview, queuedAt: HomeTiming.instant(status.held?.queuedAt))
    }
}
