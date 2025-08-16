#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class GoldSetSmokeTests: XCTestCase {
    func testServiceStreamsAndFinalizes() async throws {
        let tp = FakeTranslationProvider()
        let llm = FakeLLMEnhancer()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)
        var sawMT = false
        var sawFinal = false
        let stream = svc.translate(term: "neural network", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
        for await update in stream {
            switch update {
            case .mt: sawMT = true
            case .final(let out): sawFinal = !out.chosenText.isEmpty
            default: break
            }
        }
        XCTAssertTrue(sawMT)
        XCTAssertTrue(sawFinal)
    }
}
#endif


