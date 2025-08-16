#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class CacheServiceTests: XCTestCase {
    override func setUp() {
        DatabaseManager.shared.start()
    }

    func testMTKeyStability() {
        let key1 = CacheService.makeMTKey(term: " Hello ", src: "EN", dst: "FA", context: "x")
        let key2 = CacheService.makeMTKey(term: "hello", src: "en", dst: "fa", context: "x")
        XCTAssertEqual(key1, key2)
    }

    func testPutAndGetMT() throws {
        let resp = MTResponse(candidates: [SenseCandidate(text: "سلام دنیا", provenance: "fake")], detectedSrc: "en", usage: QuotaInfo(rpm: 1, tpm: 1, rpd: 1))
        let key = CacheService.makeMTKey(term: "Hello", src: "en", dst: "fa", context: nil)
        try CacheService.putMT(forKey: key, value: resp, ttlSeconds: 60)
        let fetched = try CacheService.getMT(forKey: key)
        XCTAssertEqual(fetched?.candidates.first?.text, "سلام دنیا")
    }
}
#endif


