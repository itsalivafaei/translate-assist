#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class LLMJSONValidatorTests: XCTestCase {
    func testDecodeValidDecisionJSON() throws {
        let json = """
        {"version":"1.0","decision":"mt","top_index":0,"rewrite":null,"explanation":"ok","confidence":0.8,"warnings":[]}
        """
        let d = try PromptFactory._decodeDecision(from: json)
        XCTAssertEqual(d.version, "1.0")
        XCTAssertEqual(d.decision, .mt)
        XCTAssertEqual(d.topIndex, 0)
    }

    func testRepairInvalidDecisionJSON() async throws {
        let broken = "garbage not json"
        let repair = PromptFactory.repairPrompt(from: broken)
        XCTAssertTrue(repair.contains("SCHEMA:"))
        // We cannot call real network, but ensure the repair prompt is non-empty and contains the broken payload
        XCTAssertTrue(repair.contains(broken))
    }
}
#endif


