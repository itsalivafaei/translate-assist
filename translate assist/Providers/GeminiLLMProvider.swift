//
//  GeminiLLMProvider.swift
//  translate assist
//
//  Phase 5: Gemini Flash-Lite adapter via Google Generative Language API.
//

import Foundation

public final class GeminiLLMProvider: LLMEnhancer {
    private let apiKey: String?
    private let modelId: String

    public init(apiKey: String?, modelId: String) {
        self.apiKey = apiKey
        self.modelId = modelId
    }

    public func decide(input: LLMDecisionInput) async throws -> LLMDecision {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AppDomainError.unauthenticatedMissingKey(provider: "Gemini")
        }
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent"
        guard let url = URL(string: urlStr) else { throw NetworkClientError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")

        let system = PromptFactory.decisionPrompt(input: input)
        let body: [String: Any] = [
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": system]]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let response = try await RateLimitScheduler.shared.schedule(provider: .gemini, costTokens: estimateTokens(for: input)) {
            try await NetworkClient.shared.send(req)
        }

        // Parse response to extract text
        struct GenText: Decodable { let text: String? }
        struct Candidate: Decodable { let content: Content }
        struct Content: Decodable { let parts: [GenText] }
        struct Root: Decodable { let candidates: [Candidate]? }

        let root = try JSONDecoder().decode(Root.self, from: response.data)
        let text = root.candidates?.first?.content.parts.first?.text ?? "{}"

        // Try first-pass decode
        if let decision = try? decodeDecision(from: text) {
            return decision
        }

        // Attempt compact repair once
        let repairPrompt = PromptFactory.repairPrompt(from: text)
        let repairBody: [String: Any] = [
            "generationConfig": [
                "temperature": 0.0,
                "responseMimeType": "application/json"
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": repairPrompt]]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: repairBody, options: [])
        let repairedResp = try await NetworkClient.shared.send(req)
        let repairedRoot = try JSONDecoder().decode(Root.self, from: repairedResp.data)
        let repairedText = repairedRoot.candidates?.first?.content.parts.first?.text ?? "{}"
        if let decision = try? decodeDecision(from: repairedText) {
            return decision
        }
        throw AppDomainError.invalidLLMJSON
    }

    private func decodeDecision(from jsonText: String) throws -> LLMDecision {
        let data = Data(jsonText.utf8)
        // Transform keys to our DTO as needed (snake_case to camelCase)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LLMDecision.self, from: data)
    }

    private func estimateTokens(for input: LLMDecisionInput) -> Int {
        // Rough estimate: characters / 4; include candidates text length
        let base = input.term.count + (input.context?.count ?? 0)
        let cands = input.candidates.reduce(0) { $0 + $1.text.count }
        return max(200, (base + cands) / 4)
    }
}


