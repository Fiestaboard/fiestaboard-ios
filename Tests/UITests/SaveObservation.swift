import Foundation

/// UI-test observation only. Never commit to a branch on one changing AX read.
enum SaveObservation {
    struct Reason: Equatable {
        let label: String
        let minY: Double
        let documentMinY: Double
    }

    struct Sample {
        /// nil means Save was absent or focus dismissal was incomplete.
        /// Reads bracket the reason queries.
        let enabledBefore: Bool?
        let enabledAfter: Bool?
        let reason: Reason?

        var state: State? {
            guard let enabledBefore, enabledBefore == enabledAfter else { return nil }
            if enabledBefore { return reason == nil ? .enabled : nil }
            guard let reason, reason.label.hasPrefix("Can't save:"),
                  reason.minY < reason.documentMinY else { return nil }
            return .disabled(reason)
        }
    }

    enum State: Equatable { case enabled, disabled(Reason) }
    enum Failure: Error { case noConsistentState }

    /// Two consecutive matching eligible samples, separated by a polling interval.
    /// This brackets and repeats AX observations; it does not claim an atomic snapshot.
    @MainActor static func requireConsistent(
        timeout: TimeInterval = 3,
        observe: () -> Sample,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> State {
        let deadline = now() + timeout
        var previous: State?
        while now() < deadline {
            let state = observe().state
            guard now() < deadline else { break }
            if let state, state == previous { return state }
            previous = state
            let remaining = deadline - now()
            if remaining > 0 { pause(min(0.1, remaining)) }
        }
        throw Failure.noConsistentState
    }
}
