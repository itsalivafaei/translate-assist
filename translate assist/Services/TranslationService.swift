//
//  TranslationService.swift
//  translate assist
//
//  Phase 6: Orchestration service that coordinates MT → LLM decision → examples.
//  Streams progressive updates and never blocks UI. Cancellable via Task.
//

import Foundation
import OSLog

public struct TranslationOutcome: Equatable {
    public let term: String
    public let src: String
    public let dst: String
    public let context: String?
    public let chosenText: String
    public let alternatives: [String]
    public let explanation: String
    public let confidence: Double
}

public enum TranslationUpdate: Equatable {
    case mt(MTResponse)
    case decision(LLMDecision)
    case examples([Example])
    case final(TranslationOutcome)
    case banner(String)
}

public final class TranslationService {
    private let translationProvider: TranslationProvider
    private let llmEnhancer: LLMEnhancer
    private let examplesProvider: ExamplesProvider
    private let glossary: GlossaryProvider
    private let metrics: MetricsProvider
    private let escalationProviderId: String = "llama-3.3-70b-versatile"
    private let signposter = OSSignposter(subsystem: "com.klewrsolutions.translate-assist", category: "translation-service")

    public init(
        translationProvider: TranslationProvider,
        llmEnhancer: LLMEnhancer,
        examplesProvider: ExamplesProvider,
        glossary: GlossaryProvider,
        metrics: MetricsProvider
    ) {
        self.translationProvider = translationProvider
        self.llmEnhancer = llmEnhancer
        self.examplesProvider = examplesProvider
        self.glossary = glossary
        self.metrics = metrics
    }

    public func translate(
        term: String,
        src: String?,
        dst: String = "fa",
        context: String? = nil,
        persona: String? = nil,
        domainPriority: [String] = ["AI/CS", "Business"]
    ) -> AsyncStream<TranslationUpdate> {
        return AsyncStream { continuation in
            let task = Task {
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continuation.yield(.banner(AppDomainError.invalidRequest(reason: "Empty term").bannerMessage))
                    continuation.finish()
                    return
                }

                do {
                    // Phase 9: record input history (best-effort, non-fatal)
                    _ = try? InputHistoryDAO.insert(text: trimmed)
                    try? InputHistoryDAO.prune(maxEntries: 100)
                    // Stage 1: MT (cached wrapper avoids network when possible)
                    let mtSpan = signposter.beginInterval("stage.mt", id: .exclusive)
                    let mt = try await translationProvider.translate(term: trimmed, src: src, dst: dst, context: context)
                    signposter.endInterval("stage.mt", mtSpan)
                    continuation.yield(.mt(mt))
                    metrics.track(event: "mt_ok", value: nil)

                    // Stage 2: LLM decision (rerank/rewrite/explain)
                    let effectiveSrc = mt.detectedSrc ?? (src ?? "en")
                    let hits = try await glossary.find(term: trimmed, domain: domainPriority.first)
                    let decisionInput = LLMDecisionInput(
                        term: trimmed,
                        src: effectiveSrc,
                        dst: dst,
                        context: context,
                        persona: persona,
                        domainPriority: domainPriority,
                        candidates: mt.candidates,
                        glossaryHits: hits
                    )

                    // Primary decision
                    let decisionSpan = signposter.beginInterval("stage.llm", id: .exclusive)
                    var decision: LLMDecision
                    do {
                        decision = try await llmEnhancer.decide(input: decisionInput)
                    } catch let err as AppDomainError {
                        signposter.endInterval("stage.llm", decisionSpan)
                        // Degrade gracefully to MT-only immediately
                        continuation.yield(.banner(err.bannerMessage))
                        let fallbackOutcome = self.makeOutcome(term: trimmed, src: effectiveSrc, dst: dst, context: context, mt: mt, decision: nil)
                        continuation.yield(.final(fallbackOutcome))
                        metrics.track(event: "llm_fallback", value: nil)

                        // Auto-recover: for rate-limit or open circuit, schedule one retry after cooldown
                        let shouldAutoRetry: Bool
                        let waitSeconds: Int
                        switch err {
                        case .rateLimited(let retryAfterSeconds):
                            shouldAutoRetry = true
                            waitSeconds = max(1, retryAfterSeconds ?? 2)
                        case .circuitOpen(_, let cooldownMs):
                            shouldAutoRetry = true
                            waitSeconds = max(1, cooldownMs / 1000)
                        case .serverUnavailable:
                            shouldAutoRetry = true
                            waitSeconds = 2
                        case .timeout:
                            shouldAutoRetry = true
                            waitSeconds = 2
                        default:
                            shouldAutoRetry = false
                            waitSeconds = 0
                        }

                        if shouldAutoRetry {
                            // Inform user about planned retry
                            continuation.yield(.banner("Retrying LLM shortly…"))
                            let retryInput = decisionInput
                            // Schedule a single retry. If cancelled (popover closed), do nothing.
                            Task.detached { [weak self] in
                                guard let self = self else { return }
                                do {
                                    try await Task.sleep(nanoseconds: UInt64(max(1, waitSeconds) * 1_000_000_000))
                                    if Task.isCancelled { return }
                                    // Attempt decision again
                                    let retryDecision = try await self.llmEnhancer.decide(input: retryInput)
                                    if Task.isCancelled { return }
                                    // Yield improved decision and outcome
                                    continuation.yield(.decision(retryDecision))
                                    let improved = self.makeOutcome(term: trimmed, src: effectiveSrc, dst: dst, context: context, mt: mt, decision: retryDecision)
                                    continuation.yield(.final(improved))
                                    self.metrics.track(event: "llm_auto_recover_ok", value: retryDecision.confidence)
                                } catch is CancellationError {
                                    // Swallow
                                } catch let e as AppDomainError {
                                    // Still failing; keep MT-only result
                                    continuation.yield(.banner(e.bannerMessage))
                                    self.metrics.track(event: "llm_auto_recover_fail", value: nil)
                                } catch {
                                    continuation.yield(.banner(AppDomainError.unknown(message: error.localizedDescription).bannerMessage))
                                    self.metrics.track(event: "llm_auto_recover_fail", value: nil)
                                }
                                // After auto-retry attempt (success or fail), proceed to examples and finish
                                let exSpan = self.signposter.beginInterval("stage.examples", id: .exclusive)
                                let examples = (try? await self.examplesProvider.search(term: trimmed, src: effectiveSrc, dst: dst, context: context)) ?? []
                                continuation.yield(.examples(examples))
                                self.signposter.endInterval("stage.examples", exSpan)
                                continuation.finish()
                            }
                        } else {
                            // Non-retriable error: proceed to examples and finish
                            Task.detached {
                                let exSpan = self.signposter.beginInterval("stage.examples", id: .exclusive)
                                let examples = (try? await self.examplesProvider.search(term: trimmed, src: effectiveSrc, dst: dst, context: context)) ?? []
                                continuation.yield(.examples(examples))
                                self.signposter.endInterval("stage.examples", exSpan)
                                continuation.finish()
                            }
                        }
                        return
                    }

                    // Glossary conflict detection
                    let glossaryPreferred = hits.first?.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
                    let chosenText = self.previewChosenText(mt: mt, decision: decision)
                    var hasGlossaryConflict = false
                    if let glossaryPreferred, !glossaryPreferred.isEmpty, chosenText != glossaryPreferred {
                        hasGlossaryConflict = true
                        continuation.yield(.banner("Glossary preference differs — review suggested term"))
                    }

                    // Escalation: if confidence < 0.65 OR glossary conflict, try a raw enhancer (70B policy tag)
                    if decision.confidence < 0.65 || hasGlossaryConflict {
                        let raw = ProvidersBootstrap.makeRawLLMEnhancer(primary: "gemini")
                        if let escalated = try? await raw.decide(input: decisionInput) {
                            // Use separate tag to avoid polluting primary cache key
                            metrics.track(event: "llm_escalate_ok", value: escalated.confidence)
                            decision = escalated
                            // Store under separate cache tag
                            let key = CacheService.makeLLMKeyFromInput(
                                term: decisionInput.term,
                                src: decisionInput.src,
                                dst: decisionInput.dst,
                                context: decisionInput.context,
                                persona: decisionInput.persona,
                                inputCandidates: decisionInput.candidates,
                                providerTag: "escalated"
                            )
                            _ = try? CacheService.putLLM(forKey: key, value: escalated)
                        } else {
                            metrics.track(event: "llm_escalate_fail", value: nil)
                        }
                    }
                    signposter.endInterval("stage.llm", decisionSpan)

                    continuation.yield(.decision(decision))

                    // Stage 3: Finalize chosen + alternatives + explanation
                    let finalizeSpan = signposter.beginInterval("stage.finalize", id: .exclusive)
                    let outcome = self.makeOutcome(term: trimmed, src: effectiveSrc, dst: dst, context: context, mt: mt, decision: decision)
                    continuation.yield(.final(outcome))
                    metrics.track(event: "llm_ok", value: decision.confidence)
                    signposter.endInterval("stage.finalize", finalizeSpan)

                    // Stage 4: Examples (fire-and-forget; non-blocking)
                    Task.detached {
                        let exSpan = self.signposter.beginInterval("stage.examples", id: .exclusive)
                        let examples = (try? await self.examplesProvider.search(term: trimmed, src: effectiveSrc, dst: dst, context: context)) ?? []
                        continuation.yield(.examples(examples))
                        self.signposter.endInterval("stage.examples", exSpan)
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.yield(.banner(AppDomainError.cancelled.bannerMessage))
                    continuation.finish()
                } catch let e as AppDomainError {
                    continuation.yield(.banner(e.bannerMessage))
                    continuation.finish()
                } catch let e as ValidationError {
                    continuation.yield(.banner(AppDomainError.validation(e).bannerMessage))
                    continuation.finish()
                } catch let e as DatabaseError {
                    continuation.yield(.banner(AppDomainError.database(e).bannerMessage))
                    continuation.finish()
                } catch {
                    continuation.yield(.banner(AppDomainError.unknown(message: error.localizedDescription).bannerMessage))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func makeOutcome(term: String, src: String, dst: String, context: String?, mt: MTResponse, decision: LLMDecision?) -> TranslationOutcome {
        let topIndex: Int
        let chosenText: String
        let explanation: String
        let confidence: Double

        if let decision {
            if decision.decision == .rewrite, let rewrite = decision.rewrite, !rewrite.isEmpty {
                chosenText = rewrite
                topIndex = decision.topIndex
            } else if mt.candidates.indices.contains(decision.topIndex) {
                chosenText = mt.candidates[decision.topIndex].text
                topIndex = decision.topIndex
            } else {
                chosenText = mt.candidates.first?.text ?? ""
                topIndex = 0
            }
            explanation = decision.explanation
            confidence = decision.confidence
        } else {
            chosenText = mt.candidates.first?.text ?? ""
            topIndex = 0
            explanation = "Using MT due to LLM unavailability."
            confidence = 0.5
        }

        let alternatives = mt.candidates.enumerated().compactMap { idx, c in idx == topIndex ? nil : c.text }
        return TranslationOutcome(
            term: term,
            src: src,
            dst: dst,
            context: context,
            chosenText: chosenText,
            alternatives: alternatives,
            explanation: explanation,
            confidence: confidence
        )
    }

    private func previewChosenText(mt: MTResponse, decision: LLMDecision) -> String {
        if decision.decision == .rewrite, let rewrite = decision.rewrite, !rewrite.isEmpty {
            return rewrite
        }
        if mt.candidates.indices.contains(decision.topIndex) {
            return mt.candidates[decision.topIndex].text
        }
        return mt.candidates.first?.text ?? ""
    }
}


