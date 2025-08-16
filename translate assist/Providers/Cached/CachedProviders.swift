//
//  CachedProviders.swift
//  translate assist
//
//  Phase 4: Cache-decorated adapters for MT and LLM providers.
//

import Foundation

public final class CachedTranslationProvider: TranslationProvider {
    private let wrapped: TranslationProvider
    private let metrics: MetricsProvider?

    public init(wrapped: TranslationProvider, metrics: MetricsProvider? = nil) {
        self.wrapped = wrapped
        self.metrics = metrics
    }

    public func translate(term: String, src: String?, dst: String, context: String?) async throws -> MTResponse {
        let effectiveSrc = src ?? "en"
        let key = CacheService.makeMTKey(term: term, src: effectiveSrc, dst: dst, context: context)
        if let cached = try? CacheService.getMT(forKey: key) {
            metrics?.track(event: "cache_hit_mt", value: nil)
            return cached
        }
        let result = try await wrapped.translate(term: term, src: src, dst: dst, context: context)
        // Use detected source when available for cache key stability on writes
        let writeSrc = result.detectedSrc ?? effectiveSrc
        let writeKey = CacheService.makeMTKey(term: term, src: writeSrc, dst: dst, context: context)
        if (try? CacheService.putMT(forKey: writeKey, value: result)) != nil {
            metrics?.track(event: "cache_put_mt", value: nil)
        } else {
            metrics?.track(event: "cache_put_mt_fail", value: nil)
        }
        return result
    }
}

public final class CachedLLMEnhancer: LLMEnhancer {
    private let wrapped: LLMEnhancer
    private let metrics: MetricsProvider?

    public init(wrapped: LLMEnhancer, metrics: MetricsProvider? = nil) {
        self.wrapped = wrapped
        self.metrics = metrics
    }

    public func decide(input: LLMDecisionInput) async throws -> LLMDecision {
        let key = CacheService.makeLLMKeyFromInput(
            term: input.term,
            src: input.src,
            dst: input.dst,
            context: input.context,
            persona: input.persona,
            inputCandidates: input.candidates
        )
        if let cached = try? CacheService.getLLM(forKey: key) {
            metrics?.track(event: "cache_hit_llm", value: nil)
            return cached
        }
        let decision = try await wrapped.decide(input: input)
        // Only cache valid, schema-conformant decisions
        if (try? CacheService.putLLM(forKey: key, value: decision)) != nil {
            metrics?.track(event: "cache_put_llm", value: nil)
        } else {
            metrics?.track(event: "cache_put_llm_fail", value: nil)
        }
        return decision
    }
}


