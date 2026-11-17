import Foundation

/// A server-advertised authentication cooldown, independent of the shell's reachability retry.
public struct LoginRetryDeadline: Sendable, Equatable {
    public let endsAt: Date

    public init?(retryAfterSeconds: Int?, receivedAt: Date) {
        guard let seconds = retryAfterSeconds, seconds >= 0,
              receivedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        endsAt = receivedAt.addingTimeInterval(TimeInterval(seconds))
    }

    public func remainingSeconds(at now: Date) -> Int {
        let remaining = ceil(endsAt.timeIntervalSince(now))
        guard remaining.isFinite else { return Int.max }
        if remaining <= 0 { return 0 }
        if remaining >= Double(Int.max) { return Int.max }
        return Int(remaining)
    }
}
