#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class GoldSetSubsetTests: XCTestCase {
    func testRunSubsetAndLogMetrics() async throws {
        let tp = FakeTranslationProvider()
        let llm = FakeLLMEnhancer()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)

        var latencies: [TimeInterval] = []
        let subset: [GoldSetItem] = [
            .helloWorld, .neuralNetwork, .machineLearning, .businessPlan, .algorithm,
            .artificialIntelligence, .deepLearning, .dataset, .transformer, .roadmap
        ]
        for item in subset {
            let start = Date()
            var sawFinal = false
            let stream = svc.translate(term: item.rawValue, src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
            for await update in stream {
                if case .final(let out) = update {
                    sawFinal = !out.chosenText.isEmpty
                }
            }
            XCTAssertTrue(sawFinal)
            latencies.append(Date().timeIntervalSince(start))
        }
        // Basic sanity: p95/p50 calculations
        let sorted = latencies.sorted()
        let p50 = sorted[Int(Double(sorted.count - 1) * 0.5)]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        // Just assert they are finite and non-negative
        XCTAssertGreaterThanOrEqual(p50, 0)
        XCTAssertGreaterThanOrEqual(p95, 0)
    }
}
#endif


