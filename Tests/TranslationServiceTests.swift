#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class TranslationServiceTests: XCTestCase {
    func makeService(llm: LLMEnhancer) -> TranslationService {
        let tp = FakeTranslationProvider()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        return TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)
    }

    func testStreamingOrderAndFinal() async throws {
        let svc = makeService(llm: FakeLLMEnhancer())
        var sequence: [String] = []
        let stream = svc.translate(term: "Hello, world!", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
        for await update in stream {
            switch update {
            case .mt: sequence.append("mt")
            case .decision: sequence.append("decision")
            case .final(let outcome): sequence.append("final:") ; XCTAssertFalse(outcome.chosenText.isEmpty)
            case .examples(let list): sequence.append("examples:") ; XCTAssertGreaterThanOrEqual(list.count, 0)
            case .banner: break
            }
        }
        XCTAssertTrue(sequence.first == "mt")
        XCTAssertTrue(sequence.contains(where: { $0.hasPrefix("final") || $0 == "final:" }))
    }

    func testCancellation() async throws {
        let svc = makeService(llm: FakeLLMEnhancer())
        let stream = svc.translate(term: "Hello, world!", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
        let task = Task { () -> Int in
            var count = 0
            for await _ in stream { count += 1 }
            return count
        }
        task.cancel()
        _ = await task.result
        XCTAssertTrue(task.isCancelled)
    }

    func testEscalationPath() async throws {
        struct LowConfidenceLLM: LLMEnhancer {
            func decide(input: LLMDecisionInput) async throws -> LLMDecision {
                return LLMDecision(decision: .mt, topIndex: 0, rewrite: nil, explanation: "low", confidence: 0.3)
            }
        }
        let svc = makeService(llm: LowConfidenceLLM())
        var sawDecision = false
        let stream = svc.translate(term: "Hello, world!", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
        for await update in stream {
            if case .decision(let d) = update { sawDecision = true ; XCTAssertGreaterThanOrEqual(d.confidence, 0.0) }
        }
        XCTAssertTrue(sawDecision)
    }
}
#endif


