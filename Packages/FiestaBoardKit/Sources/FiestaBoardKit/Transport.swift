import Foundation

public struct APIRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH" }
    public let method: Method
    public let path: [String]
    public let body: Data?
    public let timeout: TimeInterval
    /// The two bounded evaluation POSTs never write a page or send to hardware.
    public var isMutation: Bool {
        method != .get && !(method == .post && (path == ["templates", "validate"] || path == ["templates", "render"]))
    }
    public init(_ method: Method = .get, path: [String], body: Data? = nil, timeout: TimeInterval = 20) {
        self.method = method; self.path = path; self.body = body; self.timeout = timeout
    }
}
public struct APIResponse: Sendable {
    public let status: Int
    public let data: Data
    public init(status: Int, data: Data) { self.status = status; self.data = data }
}
public protocol APITransport: Sendable {
    func send(_ request: APIRequest) async throws -> APIResponse
    func resetSession() async
}
/// Memory-only, isolated to one full deployment identity; never uses a shared cookie or credential store.
public actor URLSessionTransport: APITransport {
    private let deployment: DeploymentURL
    private let session: URLSession
    private var cookies = SessionCookieJar()
    private var generation: UInt64 = 0

    public init(deployment: DeploymentURL, protocolClasses: [AnyClass] = []) {
        self.deployment = deployment
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration, delegate: RefuseRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func resetSession() {
        generation &+= 1
        cookies = SessionCookieJar()
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        let currentGeneration = generation
        let url = try deployment.apiURL(request.path)
        var wire = URLRequest(url: url)
        wire.timeoutInterval = request.timeout
        wire.httpMethod = request.method.rawValue
        wire.httpBody = request.body
        wire.httpShouldHandleCookies = false
        wire.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil { wire.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        wire.setValue(cookies.header(for: url), forHTTPHeaderField: "Cookie")
        let data: Data
        let response: URLResponse
        do {
            // Exactly one application-level task, with no retry or mutation replay.
            (data, response) = try await session.data(for: wire)
        } catch {
            guard currentGeneration == generation else { throw FiestaBoardError.staleSession }
            throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .networkUnavailable
        }
        guard currentGeneration == generation else { throw FiestaBoardError.staleSession }
        guard let http = response as? HTTPURLResponse else {
            throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .invalidResponse
        }
        if let header = http.value(forHTTPHeaderField: "Set-Cookie") { cookies.receive(header, from: url) }
        switch http.statusCode {
        case 200..<300: return APIResponse(status: http.statusCode, data: data)
        case 300..<400: throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .redirectRefused
        case 401: throw FiestaBoardError.unauthenticated
        case 412: throw FiestaBoardError.pageConflict
        case 409: throw FiestaBoardError.conflict
        case 429:
            let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
            throw FiestaBoardError.rateLimited(retryAfterSeconds: seconds)
        case 502:
            struct Partial: Decodable {
                struct Detail: Decodable { let partial: Bool; let failed_regions: [FailedRegion] }
                let detail: Detail
            }
            if let partial = try? JSONDecoder().decode(Partial.self, from: data), partial.detail.partial {
                throw FiestaBoardError.partialWrite(failedRegions: partial.detail.failed_regions)
            }
            if request.isMutation { throw FiestaBoardError.unknownMutationOutcome }
            throw FiestaBoardError.rejected(status: 502)
        case 500...599 where request.isMutation: throw FiestaBoardError.unknownMutationOutcome
        default: throw FiestaBoardError.rejected(status: http.statusCode)
        }
    }
}

final class RefuseRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Use system TLS trust validation; never answer HTTP credential challenges.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}

struct SessionCookieJar: Sendable {
    private struct Cookie: Sendable {
        let value: String
        let domain: String
        let hostOnly: Bool
        let path: String
        let secure: Bool
        let expires: Date?
    }
    private var entries: [Cookie] = []

    mutating func receive(_ header: String, from url: URL, now: Date = Date()) {
        // Split combined Set-Cookie fields only at the next cookie name, not an Expires comma.
        let pattern = ",(?=\\s*[^;,=\\s]+\\s*=)"
        let fields = header.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression).split(separator: "\n")
        guard let host = url.host?.lowercased() else { return }
        for field in fields {
            let attributes = field.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = attributes.first, let equals = first.firstIndex(of: "="),
                  first[..<equals] == "fiestaboard_session" else { continue }
            let value = String(first[first.index(after: equals)...])
            guard value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 && $0 != 59 && $0 != 44 }) else { continue }
            var domain = host
            var hostOnly = true
            var path = String(url.path.prefix(through: url.path.lastIndex(of: "/") ?? url.path.startIndex).dropLast())
            if path.isEmpty { path = "/" }
            var secure = false
            var expiry: Date?
            var maxAge: Int?
            for attribute in attributes.dropFirst() {
                let pair = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = pair[0].lowercased()
                let val = pair.count == 2 ? String(pair[1]) : ""
                switch key {
                case "domain": domain = val.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")); hostOnly = false
                case "path": if val.hasPrefix("/") { path = val }
                case "secure": secure = true
                case "max-age": maxAge = Int(val)
                default: break
                }
            }
            // This draft accepts explicit domains only equal to the deployment host.
            // It intentionally refuses parent-domain cookies, avoiding public-suffix ambiguity.
            guard domain == host else { continue }
            if let maxAge { expiry = now.addingTimeInterval(TimeInterval(maxAge)) }
            else {
                expiry = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": String(field)], for: url).first?.expiresDate
            }
            entries.removeAll { $0.domain == domain && $0.path == path }
            if expiry.map({ $0 <= now }) ?? false { continue }
            entries.append(Cookie(value: value, domain: domain, hostOnly: hostOnly, path: path, secure: secure, expires: expiry))
        }
    }

    func header(for url: URL, now: Date = Date()) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let matching = entries.filter { cookie in
            let domainMatches = host == cookie.domain || (!cookie.hostOnly && host.hasSuffix("." + cookie.domain))
            let path = url.path.isEmpty ? "/" : url.path
            let pathMatches = path == cookie.path || (path.hasPrefix(cookie.path) &&
                (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
            return domainMatches && pathMatches && (!cookie.secure || url.scheme == "https") &&
                (cookie.expires.map { $0 > now } ?? true)
        }.sorted { $0.path.count > $1.path.count }
        return matching.isEmpty ? nil : matching.map { "fiestaboard_session=" + $0.value }.joined(separator: "; ")
    }
}
