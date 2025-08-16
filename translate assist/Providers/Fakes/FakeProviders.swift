//
//  FakeProviders.swift
//  translate assist
//
//  Phase 2: In‑memory fake providers for previews/tests.
//

import Foundation

public final class FakeTranslationProvider: TranslationProvider {
    public init() {}

    public func translate(term: String, src: String?, dst: String, context: String?) async throws -> MTResponse {
        let normalizedSrc = src ?? detectSrc(for: term)
        let candidates: [SenseCandidate]
        if term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "hello, world!" {
            candidates = [
                SenseCandidate(text: "سلام دنیا", pos: nil, ipa: nil, provenance: "fake-mt"),
                SenseCandidate(text: "درود بر جهان", pos: nil, ipa: nil, provenance: "fake-mt")
            ]
        } else {
            // Very naive echo with suffix to show determinism in previews
            candidates = [
                SenseCandidate(text: "\(term) · ترجمه", pos: nil, ipa: nil, provenance: "fake-mt")
            ]
        }
        let usage = QuotaInfo(
            rpm: ProviderRateLimits.googleTranslate.rpm,
            tpm: ProviderRateLimits.googleTranslate.tpm,
            rpd: ProviderRateLimits.googleTranslate.rpd
        )
        return MTResponse(candidates: candidates, detectedSrc: normalizedSrc, usage: usage)
    }

    private func detectSrc(for text: String) -> String? {
        // If ASCII letters dominate, pretend it's English; otherwise unknown
        let letters = text.filter { $0.isLetter }
        let asciiLetters = letters.filter { $0.isASCII }
        return asciiLetters.count >= max(1, letters.count / 2) ? "en" : nil
    }
}

public final class FakeLLMEnhancer: LLMEnhancer {
    public init() {}

    public func decide(input: LLMDecisionInput) async throws -> LLMDecision {
        // Simple deterministic selector: prefer glossary if present; else first candidate.
        let topIndex = input.glossaryHits.isEmpty ? 0 : 0
        let chosen = input.candidates.indices.contains(topIndex) ? input.candidates[topIndex] : nil
        let personaHint = (input.persona?.isEmpty == false) ? " (\(input.persona ?? ""))" : ""
        let explanation = "Chose candidate \(topIndex) based on defaults\(personaHint)."
        // If persona suggests business writing, pretend we rewrote to be more formal.
        let shouldRewrite = (input.persona?.lowercased().contains("business") ?? false)
        let rewrite = shouldRewrite ? (chosen?.text ?? "").appending(" · رسمی") : nil
        let decision: LLMDecisionKind = shouldRewrite ? .rewrite : .mt
        return LLMDecision(
            decision: decision,
            topIndex: topIndex,
            rewrite: rewrite,
            explanation: explanation,
            confidence: 0.92,
            warnings: []
        )
    }
}

public final class FakeExamplesProvider: ExamplesProvider {
    public init() {}

    public func search(term: String, src: String, dst: String, context: String?) async throws -> [Example] {
        return [
            Example(srcText: "Hello, world!", dstText: "سلام دنیا!", provenance: "fake"),
            Example(srcText: "A friendly greeting.", dstText: "یک سلام دوستانه.", provenance: "fake")
        ]
    }
}

public final class FakeGlossaryProvider: GlossaryProvider {
    public init() {}

    public func find(term: String, domain: String?) async throws -> [GlossaryHit] {
        if term.lowercased().contains("model") {
            return [GlossaryHit(term: term, domain: domain, canonical: "مدل", note: "AI/CS preferred")] 
        }
        return []
    }
}

public final class FakeMetricsProvider: MetricsProvider {
    public init() {}
    public func track(event: String, value: Double?) {
        #if DEBUG
        print("[metrics] event=\(event) value=\(value ?? .nan)")
        #endif
    }
}

public enum FakeDataFactory {
    public static func sampleMTResponse() -> MTResponse {
        let usage = QuotaInfo(rpm: ProviderRateLimits.googleTranslate.rpm, tpm: ProviderRateLimits.googleTranslate.tpm, rpd: ProviderRateLimits.googleTranslate.rpd)
        return MTResponse(
            candidates: [
                SenseCandidate(text: "سلام دنیا", provenance: "fake-mt"),
                SenseCandidate(text: "درود بر جهان", provenance: "fake-mt")
            ],
            detectedSrc: "en",
            usage: usage
        )
    }

    public static func sampleDecision() -> LLMDecision {
        return LLMDecision(
            decision: .mt,
            topIndex: 0,
            rewrite: nil,
            explanation: "Selected the most common translation.",
            confidence: 0.9
        )
    }

    public static func sampleExamples() -> [Example] {
        [
            Example(srcText: "Hello, world!", dstText: "سلام دنیا!", provenance: "fake"),
            Example(srcText: "The world says hello.", dstText: "دنیا سلام می‌کند.", provenance: "fake")
        ]
    }
}


