#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class RateLimitSchedulerTests: XCTestCase {
    func testScheduleSucceedsWithSmallCost() async throws {
        let start = Date()
        let result: Int = try await RateLimitScheduler.shared.schedule(provider: .googleTranslate, costTokens: 1) {
            return 42
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result, 42)
        // Should run near-instantly under defaults
        XCTAssertLessThan(elapsed, 0.5)
    }
}
#endif


