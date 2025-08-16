//
//  GoogleTranslationProvider.swift
//  translate assist
//
//  Phase 5: Google Translate v2 adapter. Detects source when not provided.
//

import Foundation

public final class GoogleTranslationProvider: TranslationProvider {
    private let apiKey: String?

    public init(apiKey: String?) {
        self.apiKey = apiKey
    }

    public func translate(term: String, src: String?, dst: String, context: String?) async throws -> MTResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AppDomainError.unauthenticatedMissingKey(provider: "Google Translate")
        }

        let endpoint = "https://translation.googleapis.com/language/translate/v2?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw NetworkClientError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body; include q and target, plus optional source
        var body: [String: Any] = [
            "q": [term],
            "target": dst,
            "format": "text",
            "model": "nmt"
        ]
        if let src, !src.isEmpty { body["source"] = src }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        req.httpBody = data

        let costTokens = max(term.count, 1)
        let response = try await RateLimitScheduler.shared.schedule(provider: .googleTranslate, costTokens: costTokens) {
            try await NetworkClient.shared.send(req)
        }

        // Parse response
        struct GTResponse: Decodable {
            struct DataField: Decodable {
                struct Item: Decodable { let translatedText: String }
                let translations: [Item]
            }
            let data: DataField
        }

        let decoded = try JSONDecoder().decode(GTResponse.self, from: response.data)
        let texts = decoded.data.translations.map { $0.translatedText }
        let candidates = texts.map { SenseCandidate(text: $0, provenance: "google") }
        // Note: Google may return detected language in alternate endpoints; we keep provided src or default
        let detected = src // keep as-is for now; optionally add detect endpoint later
        let usage = QuotaInfo(rpm: ProviderRateLimits.googleTranslate.rpm, tpm: ProviderRateLimits.googleTranslate.tpm, rpd: ProviderRateLimits.googleTranslate.rpd)
        return MTResponse(candidates: candidates, detectedSrc: detected, usage: usage)
    }
}


