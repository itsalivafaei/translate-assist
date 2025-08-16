//
//  PromptFactory.swift
//  translate assist
//
//  Phase 5: Centralized prompt construction for LLM decisions and repair.
//

import Foundation

public enum PromptFactory {
    // Primary decision prompt requesting strict JSON only
    public static func decisionPrompt(input: LLMDecisionInput) -> String {
        let schema = """
        You are a bilingual sense disambiguator for EN/ES/ZH/HI/AR→FA. Choose the most context-appropriate Persian translation.
        Output STRICT JSON only. Do not include any prose or code fences.
        JSON schema:
        {
          "version": "1.0",
          "decision": "mt" | "rewrite" | "reject",
          "top_index": 0,
          "rewrite": "string|null",
          "explanation": "string",
          "confidence": 0.0,
          "warnings": ["string"]
        }
        """

        let payload: String
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(input)
            payload = String(decoding: data, as: UTF8.self)
        } catch {
            payload = "{ }" // Should not occur; VM validates input
        }

        let instructions = """
        SYSTEM:
        \(schema)

        USER:
        Decide based on this input JSON (fields: term, src, dst, context, persona, domainPriority, candidates, glossaryHits).
        Respond with only the JSON object. No markdown. No comments.
        Input:
        \(payload)
        """
        return instructions
    }

    // Compact repair prompt to coerce invalid outputs into strict JSON
    public static func repairPrompt(from invalid: String) -> String {
        let schemaOneLine = "{" +
        "\"version\":\"1.0\",\"decision\":\"mt|rewrite|reject\",\"top_index\":0,\"rewrite\":null,\"explanation\":\"\",\"confidence\":0.0,\"warnings\":[\"\"]}" 
        let prompt = """
        SYSTEM: Repair to strict JSON per schema. Output JSON only, no markdown/prose.
        SCHEMA: \(schemaOneLine)
        BROKEN:
        \(invalid)
        """
        return prompt
    }
}


