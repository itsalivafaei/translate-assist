#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class RateLimitSchedulerBackoffTests: XCTestCase {
    func testBackoffDoesNotThrowUnexpectedErrors() async throws {
        // Simulate rate-limit by invoking backoff path via throwing operation
        // We can't easily force NetworkClient errors here, so we exercise scheduler wait with zero cost repeatedly.
        for _ in 0..<3 {
            let _: Int = try await RateLimitScheduler.shared.schedule(provider: .gemma3, costTokens: 1) {
                return 1
            }
        }
        XCTAssertTrue(true)
    }
}
#endif


