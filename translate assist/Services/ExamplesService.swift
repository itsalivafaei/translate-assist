//
//  ExamplesService.swift
//  translate assist
//
//  Phase 6: Thin orchestration over ExamplesProvider with an in-memory cache.
//

import Foundation

public final class ExamplesService {
    private let provider: ExamplesProvider
    private let metrics: MetricsProvider?
    private let cacheTtlSeconds: TimeInterval
    private var cache: [String: (expiry: TimeInterval, items: [Example])] = [:]
    private let queue = DispatchQueue(label: "com.translateassist.examples.cache", qos: .userInitiated)

    public init(provider: ExamplesProvider, metrics: MetricsProvider? = nil, ttlSeconds: Int = 3600) {
        self.provider = provider
        self.metrics = metrics
        self.cacheTtlSeconds = TimeInterval(ttlSeconds)
    }

    public func fetch(term: String, src: String, dst: String, context: String?) async throws -> [Example] {
        let key = makeKey(term: term, src: src, dst: dst, context: context)
        if let cached = queue.sync(execute: { cache[key] }), cached.expiry > Date().timeIntervalSince1970 {
            metrics?.track(event: "cache_hit_examples", value: nil)
            return cached.items
        }
        let items = try await provider.search(term: term, src: src, dst: dst, context: context)
        queue.sync { cache[key] = (expiry: Date().timeIntervalSince1970 + cacheTtlSeconds, items: items) }
        metrics?.track(event: "cache_put_examples", value: nil)
        return items
    }

    private func makeKey(term: String, src: String, dst: String, context: String?) -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ctx = (context ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "v1|examples|src:\(src)|dst:\(dst)|term:\(trimmed)|ctx:\(ctx.hashValue)"
    }
}


