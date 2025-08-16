//
//  Errors.swift
//  translate assist
//
//  Phase 2: Typed domain errors with user‑presentable messages.
//

import Foundation

public protocol UserPresentableError: LocalizedError {
    var bannerMessage: String { get }
}

public enum AppDomainError: Error, UserPresentableError {
    case offline
    case unauthenticatedMissingKey(provider: String)
    case rateLimited(retryAfterSeconds: Int?)
    case serverUnavailable
    case timeout
    case cancelled
    case invalidRequest(reason: String)
    case invalidResponse
    case decodingFailed
    case invalidLLMJSON
    case circuitOpen(provider: String, cooldownMs: Int)
    case database(DatabaseError)
    case validation(ValidationError)
    case unknown(message: String)

    public var errorDescription: String? {
        bannerMessage
    }

    public var bannerMessage: String {
        switch self {
        case .offline:
            return "Offline — showing cache when possible"
        case .unauthenticatedMissingKey(let provider):
            return "Missing API key for \(provider). Add it in Settings."
        case .rateLimited(let retryAfter):
            if let retryAfter { return "Provider busy — retrying in \(retryAfter)s" }
            return "Provider busy — retrying shortly"
        case .serverUnavailable:
            return "Provider unavailable — try again"
        case .timeout:
            return "Request timed out — tap to retry"
        case .cancelled:
            return "Cancelled"
        case .invalidRequest(let reason):
            return "Invalid request — \(reason)"
        case .invalidResponse:
            return "Invalid response from provider"
        case .decodingFailed:
            return "Failed to decode response"
        case .invalidLLMJSON:
            return "LLM output invalid — using MT only"
        case .circuitOpen(let provider, let cooldownMs):
            let seconds = max(1, cooldownMs / 1000)
            return "LLM paused (\(provider)) — auto‑retry in \(seconds)s"
        case .database:
            return "Storage error — operation skipped"
        case .validation(let err):
            return err.errorDescription ?? "Validation failed"
        case .unknown(let message):
            return message
        }
    }
}


