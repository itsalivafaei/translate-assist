//
//  Contracts.swift
//  translate assist
//
//  Phase 2: Provider protocols and DTOs (protocol‑oriented, swappable adapters).
//

import Foundation

// MARK: - Shared DTOs

public struct QuotaInfo: Codable, Equatable {
    public let rpm: Int
    public let tpm: Int
    public let rpd: Int

    public init(rpm: Int, tpm: Int, rpd: Int) {
        self.rpm = rpm
        self.tpm = tpm
        self.rpd = rpd
    }
}

public struct SenseCandidate: Codable, Equatable {
    public let text: String
    public let pos: String?
    public let ipa: String?
    public let provenance: String

    public init(text: String, pos: String? = nil, ipa: String? = nil, provenance: String) {
        self.text = text
        self.pos = pos
        self.ipa = ipa
        self.provenance = provenance
    }
}

public struct MTResponse: Codable, Equatable {
    public let candidates: [SenseCandidate]
    public let detectedSrc: String?
    public let usage: QuotaInfo

    public init(candidates: [SenseCandidate], detectedSrc: String?, usage: QuotaInfo) {
        self.candidates = candidates
        self.detectedSrc = detectedSrc
        self.usage = usage
    }
}

public struct GlossaryHit: Codable, Equatable {
    public let term: String
    public let domain: String?
    public let canonical: String
    public let note: String?

    public init(term: String, domain: String?, canonical: String, note: String?) {
        self.term = term
        self.domain = domain
        self.canonical = canonical
        self.note = note
    }
}

public struct LLMDecisionInput: Codable, Equatable {
    public let term: String
    public let src: String
    public let dst: String
    public let context: String?
    public let persona: String?
    public let domainPriority: [String]
    public let candidates: [SenseCandidate]
    public let glossaryHits: [GlossaryHit]

    public init(term: String, src: String, dst: String = "fa", context: String?, persona: String?, domainPriority: [String], candidates: [SenseCandidate], glossaryHits: [GlossaryHit]) {
        self.term = term
        self.src = src
        self.dst = dst
        self.context = context
        self.persona = persona
        self.domainPriority = domainPriority
        self.candidates = candidates
        self.glossaryHits = glossaryHits
    }
}

public enum LLMDecisionKind: String, Codable {
    case mt
    case rewrite
    case reject
}

public struct LLMDecision: Codable, Equatable {
    public let version: String
    public let decision: LLMDecisionKind
    public let topIndex: Int
    public let rewrite: String?
    public let explanation: String
    public let confidence: Double
    public let warnings: [String]

    public init(version: String = "1.0", decision: LLMDecisionKind, topIndex: Int, rewrite: String?, explanation: String, confidence: Double, warnings: [String] = []) {
        self.version = version
        self.decision = decision
        self.topIndex = topIndex
        self.rewrite = rewrite
        self.explanation = explanation
        self.confidence = confidence
        self.warnings = warnings
    }
}

public struct Example: Codable, Equatable {
    public let srcText: String
    public let dstText: String
    public let provenance: String

    public init(srcText: String, dstText: String, provenance: String) {
        self.srcText = srcText
        self.dstText = dstText
        self.provenance = provenance
    }
}

// MARK: - Protocols

public protocol TranslationProvider {
    func translate(term: String, src: String?, dst: String, context: String?) async throws -> MTResponse
}

public protocol LLMEnhancer {
    func decide(input: LLMDecisionInput) async throws -> LLMDecision
}

public protocol ExamplesProvider {
    func search(term: String, src: String, dst: String, context: String?) async throws -> [Example]
}

public protocol GlossaryProvider {
    func find(term: String, domain: String?) async throws -> [GlossaryHit]
}

public protocol MetricsProvider {
    func track(event: String, value: Double?)
}

#if DEBUG
public enum GoldSetItem: String, CaseIterable {
    case helloWorld = "Hello, world!"
    case neuralNetwork = "neural network"
    case machineLearning = "machine learning"
    case businessPlan = "business plan"
    case algorithm = "algorithm"
    case artificialIntelligence = "artificial intelligence"
    case deepLearning = "deep learning"
    case dataset = "dataset"
    case promptEngineering = "prompt engineering"
    case transformer = "transformer"
    case attentionMechanism = "attention mechanism"
    case lossFunction = "loss function"
    case optimization = "optimization"
    case entrepreneurship = "entrepreneurship"
    case revenueModel = "revenue model"
    case stakeholder = "stakeholder"
    case roadmap = "roadmap"
    case featureRequest = "feature request"
    case productRequirement = "product requirement"
    case userStory = "user story"
    case acceptanceCriteria = "acceptance criteria"
}
#endif


