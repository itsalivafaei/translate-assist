#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class PromptFactoryTests: XCTestCase {
    func testDecisionPromptContainsSchemaAndPayload() {
        let input = LLMDecisionInput(
            term: "hello",
            src: "en",
            dst: "fa",
            context: nil,
            persona: nil,
            domainPriority: ["AI/CS"],
            candidates: [SenseCandidate(text: "سلام", provenance: "mt")],
            glossaryHits: []
        )
        let prompt = PromptFactory.decisionPrompt(input: input)
        XCTAssertTrue(prompt.contains("\"version\": \"1.0\""))
        XCTAssertTrue(prompt.contains("\"decision\""))
        XCTAssertTrue(prompt.contains("\"top_index\""))
        XCTAssertTrue(prompt.contains("\"candidates\""))
    }
}
#endif


