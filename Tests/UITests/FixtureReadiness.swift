import Foundation

/// Infrastructure initialization only: bounded idempotent health reads, never app operations.
enum FixtureReadiness {
    enum Failure: Error { case deadline, badStatus(Int), identity, missingResponse }
    typealias Reply = (status: Int, body: Data)
    typealias Attempt = (URLRequest, TimeInterval) throws -> Reply

    static func require(_ url: URL,
                        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                        pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                        attempt: Attempt? = nil) throws {
        let deadline = now() + 9
        let transport = attempt ?? send
        for index in 0..<3 {
            let remaining = deadline - now()
            guard remaining > 0 else { throw Failure.deadline }
            let limit = min(3, remaining)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: limit)
            request.httpMethod = "GET"
            do {
                let reply = try transport(request, limit)
                guard now() <= deadline else { throw Failure.deadline }
                guard reply.status == 200 else { throw Failure.badStatus(reply.status) }
                guard let object = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
                      object["fixture"] as? String == "native-onboarding" else { throw Failure.identity }
                return
            } catch let error as URLError where [.timedOut, .cannotConnectToHost, .networkConnectionLost].contains(error.code) {
                print("Fixture readiness transport attempt \(index + 1)/3 failed (\(error.code.rawValue)); remaining \(max(0, deadline - now()))s")
                guard index < 2 else { throw error }
                let delay = min(0.1, deadline - now())
                guard delay > 0 else { throw Failure.deadline }
                pause(delay)
            }
        }
    }

    private static func send(_ request: URLRequest, limit: TimeInterval) throws -> Reply {
        let result = Completion()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result.set(.failure(error)) }
            else if let response = response as? HTTPURLResponse { result.set(.success((response.statusCode, data ?? Data()))) }
            else { result.set(.failure(Failure.missingResponse)) }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + limit) == .success else {
            task.cancel()
            throw URLError(.timedOut)
        }
        return try result.get()
    }

    /// URLSession completes off-thread; both accessors protect the result with the same lock.
    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Reply, Error>?
        func set(_ value: Result<Reply, Error>) { lock.lock(); defer { lock.unlock() }; result = value }
        func get() throws -> Reply {
            lock.lock(); defer { lock.unlock() }
            guard let result else { throw Failure.missingResponse }
            return try result.get()
        }
    }
}
