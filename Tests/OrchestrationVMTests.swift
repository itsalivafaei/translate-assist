#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class OrchestrationVMTests: XCTestCase {
    func testVMUpdatesOnStream() async throws {
        let tp = FakeTranslationProvider()
        let llm = FakeLLMEnhancer()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)
        let vm = OrchestrationVM(service: svc)
        await MainActor.run {
            vm.start(term: "Hello, world!", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        await MainActor.run {
            XCTAssertFalse(vm.chosenText.isEmpty)
            XCTAssertGreaterThanOrEqual(vm.examples.count, 0)
        }
    }

    func testVMCancel() async throws {
        let tp = FakeTranslationProvider()
        let llm = FakeLLMEnhancer()
        let ex = FakeExamplesProvider()
        let gl = FakeGlossaryProvider()
        let metrics = FakeMetricsProvider()
        let svc = TranslationService(translationProvider: tp, llmEnhancer: llm, examplesProvider: ex, glossary: gl, metrics: metrics)
        let vm = OrchestrationVM(service: svc)
        await MainActor.run {
            vm.start(term: "Hello, world!", src: "en", dst: "fa", context: nil, persona: nil, domainPriority: ["AI/CS"]) 
            vm.cancel()
        }
        XCTAssertFalse(vm.isTranslating)
    }
}
#endif


