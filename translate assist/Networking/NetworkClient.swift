//
//  NetworkClient.swift
//  translate assist
//
//  Phase 3: URLSession client with per-request timeout, request IDs,
//  structured logs (os.Logger), and signposts.
//

import Foundation
import OSLog

public struct RateLimitHints: Equatable {
    public let retryAfterSeconds: Int?
    public let limitRequests: Int?
    public let remainingRequests: Int?
    public let resetRequestsSeconds: Int?
    public let limitTokens: Int?
    public let remainingTokens: Int?
    public let resetTokensSeconds: Int?
}

public struct NetworkResponse {
    public let data: Data
    public let http: HTTPURLResponse
    public let requestId: String
    public let hints: RateLimitHints
}

public enum NetworkClientError: Error {
    case invalidURL
    case requestFailed(status: Int, requestId: String, hints: RateLimitHints)
    case offline
    case timeout
    case cancelled
    case unknown(message: String)
}

public final class NetworkClient {
    public static let shared = NetworkClient()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.klewrsolutions.translate-assist", category: "network")
    private let signposter = OSSignposter(subsystem: "com.klewrsolutions.translate-assist", category: "network")

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> NetworkResponse {
        var req = request
        // Apply timeout if not set by caller
        if req.timeoutInterval <= 0 {
            req.timeoutInterval = Double(Constants.requestTimeoutMs) / 1000.0
        }
        // Attach request id
        let requestId = UUID().uuidString
        req.setValue(requestId, forHTTPHeaderField: "X-Request-ID")

        let begin = signposter.beginInterval("network.request", id: .exclusive)
        logger.debug("➡️ \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "?") id=\(requestId) timeoutMs=\(Constants.requestTimeoutMs)")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                signposter.endInterval("network.request", begin)
                throw NetworkClientError.unknown(message: "Non-HTTP response")
            }
            let hints = parseRateLimitHints(http)
            logger.debug("⬅️ status=\(http.statusCode) id=\(requestId) retryAfter=\(hints.retryAfterSeconds ?? -1)")
            signposter.endInterval("network.request", begin)
            if (200..<300).contains(http.statusCode) {
                return NetworkResponse(data: data, http: http, requestId: requestId, hints: hints)
            } else if http.statusCode == 408 {
                throw NetworkClientError.timeout
            } else if http.statusCode == 429 || http.statusCode == 503 {
                throw NetworkClientError.requestFailed(status: http.statusCode, requestId: requestId, hints: hints)
            } else {
                throw NetworkClientError.requestFailed(status: http.statusCode, requestId: requestId, hints: hints)
            }
        } catch let urlError as URLError {
            signposter.endInterval("network.request", begin)
            switch urlError.code {
            case .timedOut:
                throw NetworkClientError.timeout
            case .notConnectedToInternet:
                throw NetworkClientError.offline
            case .cancelled:
                throw NetworkClientError.cancelled
            default:
                throw NetworkClientError.unknown(message: urlError.localizedDescription)
            }
        } catch {
            signposter.endInterval("network.request", begin)
            throw error
        }
    }

    private func parseRateLimitHints(_ http: HTTPURLResponse) -> RateLimitHints {
        func intHeader(_ name: String) -> Int? {
            if let raw = http.value(forHTTPHeaderField: name) { return Int(raw) }
            return nil
        }
        let retryAfter = intHeader("retry-after") ?? intHeader("Retry-After")
        let hints = RateLimitHints(
            retryAfterSeconds: retryAfter,
            limitRequests: intHeader("x-ratelimit-limit-requests"),
            remainingRequests: intHeader("x-ratelimit-remaining-requests"),
            resetRequestsSeconds: intHeader("x-ratelimit-reset-requests"),
            limitTokens: intHeader("x-ratelimit-limit-tokens"),
            remainingTokens: intHeader("x-ratelimit-remaining-tokens"),
            resetTokensSeconds: intHeader("x-ratelimit-reset-tokens")
        )
        return hints
    }
}


