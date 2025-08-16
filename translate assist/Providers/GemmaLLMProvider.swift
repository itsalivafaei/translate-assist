//
//  GemmaLLMProvider.swift
//  translate assist
//
//  Phase 5: Gemma 3 adapter (placeholder: same API shape as Gemini for now).
//  This can be pointed to Groq or Google endpoints depending on availability.
//

import Foundation

public final class GemmaLLMProvider: LLMEnhancer {
    private let endpoint: URL

    public init(endpoint: URL) {
        self.endpoint = endpoint
    }

    public func decide(input: LLMDecisionInput) async throws -> LLMDecision {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // This assumes a text completion endpoint that accepts a single prompt
        let prompt = PromptFactory.decisionPrompt(input: input)
        let body: [String: Any] = [
            "prompt": prompt,
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let response = try await RateLimitScheduler.shared.schedule(provider: .gemma3, costTokens: estimateTokens(for: input)) {
            try await NetworkClient.shared.send(req)
        }
        // Assume the service returns { text: "..." }
        struct Root: Decodable { let text: String }
        let root = try JSONDecoder().decode(Root.self, from: response.data)
        let text = root.text

        if let decision = try? decodeDecision(from: text) { return decision }

        // Try a single repair pass using the same endpoint
        let repair = PromptFactory.repairPrompt(from: text)
        let repairBody: [String: Any] = ["prompt": repair, "temperature": 0.0]
        req.httpBody = try JSONSerialization.data(withJSONObject: repairBody, options: [])
        let repaired = try await NetworkClient.shared.send(req)
        let repairedText = (try? JSONDecoder().decode(Root.self, from: repaired.data).text) ?? "{}"
        if let decision = try? decodeDecision(from: repairedText) { return decision }
        throw AppDomainError.invalidLLMJSON
    }

    private func decodeDecision(from jsonText: String) throws -> LLMDecision {
        let data = Data(jsonText.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LLMDecision.self, from: data)
    }

    private func estimateTokens(for input: LLMDecisionInput) -> Int {
        let base = input.term.count + (input.context?.count ?? 0)
        let cands = input.candidates.reduce(0) { $0 + $1.text.count }
        return max(200, (base + cands) / 4)
    }
}


