#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class NetworkHintsTests: XCTestCase {
    func testRateLimitHintsStruct() {
        let hints = RateLimitHints(retryAfterSeconds: 2, limitRequests: 1000, remainingRequests: 998, resetRequestsSeconds: 60, limitTokens: nil, remainingTokens: nil, resetTokensSeconds: nil)
        XCTAssertEqual(hints.retryAfterSeconds, 2)
        XCTAssertEqual(hints.limitRequests, 1000)
        XCTAssertEqual(hints.remainingRequests, 998)
        XCTAssertEqual(hints.resetRequestsSeconds, 60)
    }
}
#endif


