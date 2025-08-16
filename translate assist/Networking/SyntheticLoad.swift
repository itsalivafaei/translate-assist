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

    private static func pretendNetwork(_ i: Int) async throws -> String {
        // Random 50–150ms latency to simulate work
        try await Task.sleep(nanoseconds: UInt64(Int.random(in: 50...150) * 1_000_000))
        return "ok-\(i)"
    }
}


