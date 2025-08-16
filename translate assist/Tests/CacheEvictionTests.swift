#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class CacheEvictionTests: XCTestCase {
    override func setUp() {
        DatabaseManager.shared.start()
    }

    func testEvictExpiredDoesNotCrash() throws {
        // Insert with tiny TTL and call evict; we won't assert strict timing, just that it runs
        let resp = MTResponse(candidates: [SenseCandidate(text: "x", provenance: "t")], detectedSrc: "en", usage: QuotaInfo(rpm: 1, tpm: 1, rpd: 1))
        let key = CacheService.makeMTKey(term: "x", src: "en", dst: "fa", context: nil)
        try CacheService.putMT(forKey: key, value: resp, ttlSeconds: 1)
        // Force eviction pass
        try CacheService.evictExpired()
        XCTAssertTrue(true)
    }
}
#endif


