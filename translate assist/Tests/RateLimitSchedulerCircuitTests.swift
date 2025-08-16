#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class RateLimitSchedulerCircuitTests: XCTestCase {
    override func setUp() async throws {
        RateLimitScheduler.shared._reset()
    }

    func testCircuitOpenErrorWhenForced() async throws {
        // Force open the circuit for gemini for 1 second
        RateLimitScheduler.shared._forceOpenCircuit(provider: .gemini, seconds: 1.0)
        do {
            let _: Int = try await RateLimitScheduler.shared.schedule(provider: .gemini, costTokens: 1) {
                return 1
            }
            XCTFail("Expected circuit open error")
        } catch let err as AppDomainError {
            switch err {
            case .circuitOpen(let provider, _):
                XCTAssertTrue(provider.contains("gemini"))
            default:
                XCTFail("Unexpected error: \(err)")
            }
        }
    }

    func testBackoffEnvOverrides() async throws {
        // Ensure env knobs exist; we cannot change env at runtime, but we can at least call schedule
        let start = Date()
        let result: Int = try await RateLimitScheduler.shared.schedule(provider: .googleTranslate, costTokens: 1) {
            return 7
        }
        XCTAssertEqual(result, 7)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
#endif


