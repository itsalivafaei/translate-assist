#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class LLMFallbackTests: XCTestCase {
    func testInvalidJSONTriggersMTOnlyBanner() async throws {
        struct InvalidJSONLLM: LLMEnhancer {
            func decide(input: LLMDecisionInput) async throws -> LLMDecision {
                throw AppDomainError.invalidLLMJSON
            }
        }
        let tp = FakeTranslationProvider()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: InvalidJSONLLM(), examplesProvider: ex, glossary: gl, metrics: metrics)
        var sawBanner = false
        var sawFinal = false
        let stream = svc.translate(term: "hello", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
        for await update in stream {
            switch update {
            case .banner(let message):
                if message.contains("LLM output invalid") { sawBanner = true }
            case .final(let out):
                sawFinal = !out.chosenText.isEmpty
            default:
                break
            }
        }
        XCTAssertTrue(sawBanner)
        XCTAssertTrue(sawFinal)
    }

    func testPersonaBusinessTriggersRewriteInFakeLLM() async throws {
        let tp = FakeTranslationProvider()
        let llm = FakeLLMEnhancer()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)
        var finalText: String = ""
        let stream = svc.translate(term: "hello", src: "en", dst: "fa", context: nil, persona: "business_write", domainPriority: ["Business"]) 
        for await update in stream {
            if case .final(let out) = update { finalText = out.chosenText }
        }
        // FakeLLM appends " · رسمی" on rewrite for business persona
        XCTAssertTrue(finalText.contains("· رسمی"))
    }
}
#endif


