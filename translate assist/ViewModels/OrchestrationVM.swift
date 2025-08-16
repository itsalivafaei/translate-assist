//
//  OrchestrationVM.swift
//  translate assist
//
//  Phase 6: ViewModel that binds TranslationService streaming updates to UI state.
//

import Foundation
import SwiftUI

@MainActor
public final class OrchestrationVM: ObservableObject {
    private let service: TranslationService

    @Published public private(set) var mtCandidates: [SenseCandidate] = []
    @Published public private(set) var chosenText: String = ""
    @Published public private(set) var alternatives: [String] = []
    @Published public private(set) var explanation: String = ""
    @Published public private(set) var confidence: Double = 0
    @Published public private(set) var examples: [Example] = []
    @Published public private(set) var banner: String? = nil
    @Published public private(set) var isTranslating: Bool = false

    private var currentTask: Task<Void, Never>? = nil

    public init(service: TranslationService) {
        self.service = service
        NotificationCenter.default.addObserver(forName: .menubarPopoverWillClose, object: nil, queue: .main) { [weak self] _ in
            self?.cancel()
        }
    }

    public func start(term: String, src: String? = nil, dst: String = "fa", context: String? = nil, persona: String? = nil, domainPriority: [String] = ["AI/CS","Business"]) {
        cancel()
        isTranslating = true
        banner = nil
        examples = []
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = service.translate(term: term, src: src, dst: dst, context: context, persona: persona, domainPriority: domainPriority)
            for await update in stream {
                if Task.isCancelled { break }
                switch update {
                case .mt(let mt):
                    mtCandidates = mt.candidates
                case .decision:
                    break
                case .final(let outcome):
                    chosenText = outcome.chosenText
                    alternatives = outcome.alternatives
                    explanation = outcome.explanation
                    confidence = outcome.confidence
                    isTranslating = false
                case .examples(let list):
                    examples = list
                case .banner(let message):
                    banner = message
                }
            }
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTranslating = false
    }
}

#if DEBUG
extension OrchestrationVM {
    public static func makePreview() -> OrchestrationVM {
        let tp = FakeTranslationProvider()
        let llm = FakeLLMEnhancer()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)
        let vm = OrchestrationVM(service: svc)
        // Populate sample state
        vm.mtCandidates = [
            SenseCandidate(text: "سلام دنیا", provenance: "fake-mt"),
            SenseCandidate(text: "درود بر جهان", provenance: "fake-mt")
        ]
        vm.chosenText = "سلام دنیا"
        vm.alternatives = ["درود بر جهان"]
        vm.explanation = "Selected the most common translation."
        vm.confidence = 0.86
        vm.examples = [
            Example(srcText: "Hello, world!", dstText: "سلام دنیا!", provenance: "tatoeba"),
            Example(srcText: "A friendly greeting.", dstText: "یک سلام دوستانه.", provenance: "tatoeba")
        ]
        vm.banner = nil
        vm.isTranslating = false
        return vm
    }
}
#endif


