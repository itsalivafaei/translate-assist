//
//  TranslationVM.swift
//  translate assist
//
//  Phase 2: Lightweight VM to drive previews using fake providers.
//

import Foundation
import SwiftUI

@MainActor
public final class TranslationVM: ObservableObject {
    private let translationProvider: TranslationProvider
    private let llmEnhancer: LLMEnhancer
    private let glossary: GlossaryProvider
    private let examplesProvider: ExamplesProvider
    private let metrics: MetricsProvider

    @Published public private(set) var topText: String = ""
    @Published public private(set) var alternatives: [String] = []
    @Published public private(set) var explanation: String = ""
    @Published public private(set) var banner: String? = nil

    public init(
        translationProvider: TranslationProvider,
        llmEnhancer: LLMEnhancer,
        glossary: GlossaryProvider,
        examplesProvider: ExamplesProvider,
        metrics: MetricsProvider
    ) {
        self.translationProvider = translationProvider
        self.llmEnhancer = llmEnhancer
        self.glossary = glossary
        self.examplesProvider = examplesProvider
        self.metrics = metrics
    }

    public func load(
        term: String,
        src: String?,
        dst: String = "fa",
        context: String? = nil,
        persona: String? = nil,
        domainPriority: [String] = ["AI/CS", "Business"]
    ) async {
        do {
            let mt = try await translationProvider.translate(term: term, src: src, dst: dst, context: context)
            let hits = try await glossary.find(term: term, domain: domainPriority.first)
            let input = LLMDecisionInput(
                term: term,
                src: mt.detectedSrc ?? (src ?? "en"),
                dst: dst,
                context: context,
                persona: persona,
                domainPriority: domainPriority,
                candidates: mt.candidates,
                glossaryHits: hits
            )
            let decision = try await llmEnhancer.decide(input: input)

            let chosen: String
            if decision.decision == .rewrite, let rewrite = decision.rewrite, !rewrite.isEmpty {
                chosen = rewrite
            } else if mt.candidates.indices.contains(decision.topIndex) {
                chosen = mt.candidates[decision.topIndex].text
            } else {
                chosen = mt.candidates.first?.text ?? ""
            }

            topText = chosen
            alternatives = mt.candidates.enumerated().compactMap { idx, c in idx == decision.topIndex ? nil : c.text }
            explanation = decision.explanation
            banner = nil

            metrics.track(event: "phase2_preview_ok", value: nil)
            _ = try? await examplesProvider.search(term: term, src: input.src, dst: dst, context: context) // warmup only
        } catch let e as AppDomainError {
            banner = e.bannerMessage
        } catch let e as ValidationError {
            banner = AppDomainError.validation(e).bannerMessage
        } catch let e as DatabaseError {
            banner = AppDomainError.database(e).bannerMessage
        } catch {
            banner = AppDomainError.unknown(message: error.localizedDescription).bannerMessage
        }
    }
}


