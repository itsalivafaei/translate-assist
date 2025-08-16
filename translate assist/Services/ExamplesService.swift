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

// MARK: - Phase 9: SRS and Termbank services

public final class SRSService {
    public init() {}

    public func dueNow(limit: Int = 10) throws -> [ReviewLog] {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        return try ReviewLogDAO.dueBefore(nowIso, limit: limit, offset: 0)
    }

    public func recordReview(for termId: Int64, success: Bool) throws {
        // Simple SM-2 inspired minimal scheduling: adjust ease and interval
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let prev = try ReviewLogDAO.latestForTerm(termId) ?? ReviewLog(
            id: 0, termId: termId, dueAtIso: formatter.string(from: now), ease: 2.5, intervalDays: 0, success: true, createdAtIso: formatter.string(from: now)
        )
        let newEase = max(1.3, min(2.6, prev.ease + (success ? 0.1 : -0.2)))
        let newInterval: Int
        if prev.intervalDays <= 0 { newInterval = success ? 1 : 0 }
        else if prev.intervalDays == 1 { newInterval = success ? 3 : 1 }
        else { newInterval = success ? Int(Double(prev.intervalDays) * newEase) : 1 }
        let dueDate = Calendar.current.date(byAdding: .day, value: newInterval, to: now) ?? now
        let dueIso = formatter.string(from: dueDate)
        _ = try ReviewLogDAO.insert(termId: termId, dueAtIso: dueIso, ease: newEase, intervalDays: newInterval, success: success)
    }
}

public final class TermbankService {
    public init() {}

    public func saveTerm(src: String, dst: String, lemma: String, primarySense: SenseInput, examples: [ExampleInput]) throws -> Int64 {
        let termId = try TermDAO.insert(src: src, dst: dst, lemma: lemma)
        _ = try SenseDAO.insert(
            termId: termId,
            canonical: primarySense.canonical,
            variants: primarySense.variants,
            domain: primarySense.domain,
            notes: primarySense.notes,
            style: primarySense.style,
            source: primarySense.source,
            confidence: primarySense.confidence
        )
        for ex in examples {
            _ = try ExampleDAO.insert(termId: termId, srcText: ex.srcText, dstText: ex.dstText, provenance: ex.provenance)
        }
        return termId
    }

    public func recentTerms(limit: Int = 10) throws -> [Term] {
        try TermDAO.recent(limit: limit)
    }
}

public struct SenseInput {
    public let canonical: String
    public let variants: String?
    public let domain: String?
    public let notes: String?
    public let style: String?
    public let source: String?
    public let confidence: Double?

    public init(canonical: String, variants: String?, domain: String?, notes: String?, style: String?, source: String?, confidence: Double?) {
        self.canonical = canonical
        self.variants = variants
        self.domain = domain
        self.notes = notes
        self.style = style
        self.source = source
        self.confidence = confidence
    }
}

public struct ExampleInput {
    public let srcText: String
    public let dstText: String
    public let provenance: String?

    public init(srcText: String, dstText: String, provenance: String?) {
        self.srcText = srcText
        self.dstText = dstText
        self.provenance = provenance
    }
}


