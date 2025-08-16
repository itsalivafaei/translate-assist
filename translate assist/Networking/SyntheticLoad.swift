//
//  SyntheticLoad.swift
//  translate assist
//
//  Phase 3: Simple synthetic load utility to validate scheduler behavior.
//

import Foundation

public enum SyntheticLoadTest {
    public static func runQuickBurst() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<max(1, Constants.schedulerBurstSize) * 4 {
                group.addTask {
                    do {
                        _ = try await RateLimitScheduler.shared.schedule(provider: .gemini, costTokens: 200) {
                            try await pretendNetwork(i)
                        }
                    } catch {
                        // Swallow; this is a synthetic test hook.
                    }
                }
            }
        }
    }

    public static func simulateRateLimitStorm() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try await RateLimitScheduler.shared.schedule(provider: .gemma3, costTokens: 400) {
                            try await simulated429()
                        }
                    } catch {
                        // Expected during storm
                    }
                }
            }
        }
    }

    private static func pretendNetwork(_ i: Int) async throws -> String {
        // Random 50–150ms latency to simulate work
        try await Task.sleep(nanoseconds: UInt64(Int.random(in: 50...150) * 1_000_000))
        return "ok-\(i)"
    }

    private static func simulated429() async throws -> String {
        struct DummyHints: Error {}
        // Simulate a short work then a 429-equivalent by throwing requestFailed
        try await Task.sleep(nanoseconds: 50_000_000)
        throw NetworkClientError.requestFailed(status: 429, requestId: UUID().uuidString, hints: RateLimitHints(retryAfterSeconds: 1, limitRequests: 30, remainingRequests: 0, resetRequestsSeconds: 60, limitTokens: 6000, remainingTokens: 0, resetTokensSeconds: 60))
    }
}


