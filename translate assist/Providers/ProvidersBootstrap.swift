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

    // Raw enhancer without cache decoration (used for escalation so its outputs
    // do not collide with the primary LLM cache key).
    public static func makeRawLLMEnhancer(primary: String = "gemini") -> LLMEnhancer {
        let secrets = SecretsLoader.load()
        if primary == "gemini" {
            return GeminiLLMProvider(apiKey: secrets.geminiApiKey, modelId: secrets.geminiModelId)
        } else {
            return GemmaLLMProvider(apiKey: secrets.geminiApiKey, modelId: secrets.gemma3ModelId)
        }
    }

    public static func makeExamplesProvider() -> ExamplesProvider {
        // Prefer Tatoeba provider; fallback to fake if needed later
        return TatoebaExamplesProvider()
    }

    public static func makeGlossaryProvider() -> GlossaryProvider {
        // Phase 6 MVP: Use fake glossary; wire real provider later
        return FakeGlossaryProvider()
    }

    public static func makeMetricsProvider() -> MetricsProvider {
        return DBMetricsProvider()
    }
}


