//
//  ProvidersBootstrap.swift
//  translate assist
//
//  Convenience factory to assemble providers with Secrets/env and caching.
//

import Foundation

public enum ProvidersBootstrap {
    public static func makeTranslationProvider(metrics: MetricsProvider? = nil) -> TranslationProvider {
        let secrets = SecretsLoader.load()
        let base = GoogleTranslationProvider(apiKey: secrets.googleTranslateApiKey)
        return CachedTranslationProvider(wrapped: base, metrics: metrics)
    }

    public static func makeLLMEnhancer(primary: String = "gemini", metrics: MetricsProvider? = nil) -> LLMEnhancer {
        let secrets = SecretsLoader.load()
        let enhancer: LLMEnhancer
        if primary == "gemini" {
            enhancer = GeminiLLMProvider(apiKey: secrets.geminiApiKey, modelId: secrets.geminiModelId)
        } else {
            enhancer = GemmaLLMProvider(apiKey: secrets.geminiApiKey, modelId: secrets.gemma3ModelId)
        }
        return CachedLLMEnhancer(wrapped: enhancer, metrics: metrics)
    }
}


