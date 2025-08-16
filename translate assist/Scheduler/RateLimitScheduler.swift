//
//  RateLimitScheduler.swift
//  translate assist
//
//  Phase 3: Token-bucket limiter per provider with exponential backoff
//  and a 60s circuit-breaker, honoring rate-limit headers.
//

import Foundation
import OSLog

public enum ProviderKind: String, CaseIterable, Sendable {
    case gemma3
    case gemini
    case googleTranslate
}

public final class RateLimitScheduler: @unchecked Sendable {
    public static let shared = RateLimitScheduler()

    private struct Bucket: Sendable {
        var rpmCapacity: Int
        var tpmCapacity: Int
        var rpdCapacity: Int
        var rpmTokens: Double
        var tpmTokens: Double
        var rpdTokens: Double
        var lastRefill: TimeInterval
        var circuitOpenUntil: TimeInterval
        var consecutiveFailures: Int
    }

    private let logger = Logger(subsystem: "com.klewrsolutions.translate-assist", category: "scheduler")
    private var buckets: [ProviderKind: Bucket]
    private let queue = DispatchQueue(label: "com.translateassist.scheduler", qos: .userInitiated)
    private let defaults = UserDefaults.standard

    private init() {
        let now = Date().timeIntervalSince1970
        buckets = [
            .gemma3: Bucket(
                rpmCapacity: ProviderRateLimits.gemma3.rpm,
                tpmCapacity: ProviderRateLimits.gemma3.tpm,
                rpdCapacity: ProviderRateLimits.gemma3.rpd,
                rpmTokens: Double(ProviderRateLimits.gemma3.rpm),
                tpmTokens: Double(ProviderRateLimits.gemma3.tpm),
                rpdTokens: Double(ProviderRateLimits.gemma3.rpd),
                lastRefill: now, circuitOpenUntil: 0, consecutiveFailures: 0
            ),
            .gemini: Bucket(
                rpmCapacity: ProviderRateLimits.gemini.rpm,
                tpmCapacity: ProviderRateLimits.gemini.tpm,
                rpdCapacity: ProviderRateLimits.gemini.rpd,
                rpmTokens: Double(ProviderRateLimits.gemini.rpm),
                tpmTokens: Double(ProviderRateLimits.gemini.tpm),
                rpdTokens: Double(ProviderRateLimits.gemini.rpd),
                lastRefill: now, circuitOpenUntil: 0, consecutiveFailures: 0
            ),
            .googleTranslate: Bucket(
                rpmCapacity: ProviderRateLimits.googleTranslate.rpm,
                tpmCapacity: ProviderRateLimits.googleTranslate.tpm,
                rpdCapacity: ProviderRateLimits.googleTranslate.rpd,
                rpmTokens: Double(ProviderRateLimits.googleTranslate.rpm),
                tpmTokens: Double(ProviderRateLimits.googleTranslate.tpm),
                rpdTokens: Double(ProviderRateLimits.googleTranslate.rpd),
                lastRefill: now, circuitOpenUntil: 0, consecutiveFailures: 0
            )
        ]
        // Restore persisted circuit-open timestamps if any
        for provider in ProviderKind.allCases {
            if var b = buckets[provider] {
                let key = self.persistKey(for: provider)
                if let until = defaults.object(forKey: key) as? Double {
                    let now = Date().timeIntervalSince1970
                    if until > now {
                        b.circuitOpenUntil = until
                    } else {
                        defaults.removeObject(forKey: key)
                        b.circuitOpenUntil = 0
                    }
                    buckets[provider] = b
                }
            }
        }
    }

    public func schedule<T>(provider: ProviderKind, costTokens: Int, operation: @escaping () async throws -> T) async throws -> T {
        try await waitForCapacity(provider: provider, costTokens: costTokens)
        do {
            let result = try await operation()
            registerSuccess(provider: provider)
            return result
        } catch NetworkClientError.requestFailed(let status, _, let hints) where status == 429 || status == 503 {
            try await backoff(provider: provider, hints: hints)
            throw AppDomainError.rateLimited(retryAfterSeconds: hints.retryAfterSeconds)
        } catch NetworkClientError.timeout {
            try await backoff(provider: provider, hints: RateLimitHints(retryAfterSeconds: nil, limitRequests: nil, remainingRequests: nil, resetRequestsSeconds: nil, limitTokens: nil, remainingTokens: nil, resetTokensSeconds: nil))
            throw AppDomainError.timeout
        } catch NetworkClientError.offline {
            // Do not backoff or trip circuit for offline; surface cleanly to UI
            throw AppDomainError.offline
        } catch {
            registerFailure(provider: provider)
            throw error
        }
    }

    // MARK: - Internals

    private func waitForCapacity(provider: ProviderKind, costTokens: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                var bucket = self.buckets[provider]!
                let now = Date().timeIntervalSince1970
                if bucket.circuitOpenUntil > now {
                    let remainingMs = Int((bucket.circuitOpenUntil - now) * 1000)
                    continuation.resume(throwing: AppDomainError.circuitOpen(provider: provider.rawValue, cooldownMs: max(1000, remainingMs)))
                    return
                }
                refill(&bucket, now: now)
                // RPM accounts for requests; TPM accounts for character tokens
                let rpmNeed = 1.0
                let tpmNeed = Double(max(1, costTokens))
                if bucket.rpmTokens >= rpmNeed && bucket.tpmTokens >= tpmNeed {
                    bucket.rpmTokens -= rpmNeed
                    bucket.tpmTokens -= Double(costTokens)
                    self.buckets[provider] = bucket
                    continuation.resume()
                } else {
                    // Not enough tokens; compute delay until next refill
                    let rpmPerSec = Double(bucket.rpmCapacity) / 60.0
                    let tpmPerSec = Double(bucket.tpmCapacity) / 60.0
                    let rpmShortfall = max(0, rpmNeed - bucket.rpmTokens)
                    let tpmShortfall = max(0, tpmNeed - bucket.tpmTokens)
                    let delay = max(rpmShortfall / rpmPerSec, tpmShortfall / tpmPerSec)
                    self.logger.debug("Queueing request for \(provider.rawValue); delay ~\(String(format: "%.2f", delay))s")
                    self.queue.asyncAfter(deadline: .now() + delay) { [self] in
                        self.buckets[provider] = bucket
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func refill(_ bucket: inout Bucket, now: TimeInterval) {
        let seconds = max(0, now - bucket.lastRefill)
        bucket.lastRefill = now
        bucket.rpmTokens = min(Double(bucket.rpmCapacity), bucket.rpmTokens + Double(bucket.rpmCapacity) * seconds / 60.0)
        bucket.tpmTokens = min(Double(bucket.tpmCapacity), bucket.tpmTokens + Double(bucket.tpmCapacity) * seconds / 60.0)
        bucket.rpdTokens = min(Double(bucket.rpdCapacity), bucket.rpdTokens + Double(bucket.rpdCapacity) * seconds / (24.0 * 3600.0))
    }

    private func backoff(provider: ProviderKind, hints: RateLimitHints) async throws {
        queue.sync {
            if var b = self.buckets[provider] {
                b.consecutiveFailures = (b.consecutiveFailures) + 1
                self.buckets[provider] = b
            }
        }
        let attempt = queue.sync { self.buckets[provider]?.consecutiveFailures ?? 1 }
        // Allow test-time override of backoff timings via environment (milliseconds)
        let baseMs = Env.double("RL_BACKOFF_BASE_MS", default: 300.0)
        let capMs = Env.double("RL_BACKOFF_CAP_MS", default: 8000.0)
        let base: Double = baseMs / 1000.0
        let cap: Double = capMs / 1000.0
        let jitter: Double = Double.random(in: 0...0.25)
        let retry = hints.retryAfterSeconds.map { Double($0) } ?? min(cap, base * pow(2.0, Double(attempt)) + jitter)
        logger.warning("Backoff for \(provider.rawValue) attempt=\(attempt) sleep=\(String(format: "%.2f", retry))s rl_requests=\(hints.remainingRequests ?? -1)/\(hints.limitRequests ?? -1) rl_tokens=\(hints.remainingTokens ?? -1)/\(hints.limitTokens ?? -1) reset_req_s=\(hints.resetRequestsSeconds ?? -1) reset_tok_s=\(hints.resetTokensSeconds ?? -1)")
        try await Task.sleep(nanoseconds: UInt64(retry * 1_000_000_000))
        if attempt >= 3 {
            let overrideCooldownMs = Env.double("RL_CIRCUIT_COOLDOWN_MS", default: Double(Constants.circuitBreakerCooldownMs))
            let cooldown = overrideCooldownMs / 1000.0
            queue.sync {
                if var b = self.buckets[provider] {
                    b.circuitOpenUntil = Date().timeIntervalSince1970 + cooldown
                    self.buckets[provider] = b
                }
            }
            // Persist circuit until to survive short restarts
            let until = queue.sync { self.buckets[provider]?.circuitOpenUntil ?? 0 }
            defaults.set(until, forKey: persistKey(for: provider))
            logger.error("Circuit opened for \(provider.rawValue) cooldown_s=\(cooldown, privacy: .public) rl_requests=\(hints.remainingRequests ?? -1)/\(hints.limitRequests ?? -1) rl_tokens=\(hints.remainingTokens ?? -1)/\(hints.limitTokens ?? -1)")
        }
    }

    private func registerSuccess(provider: ProviderKind) {
        queue.sync {
            if var b = self.buckets[provider] {
                b.consecutiveFailures = 0
                b.circuitOpenUntil = 0
                self.buckets[provider] = b
            }
        }
        defaults.removeObject(forKey: persistKey(for: provider))
    }

    private func registerFailure(provider: ProviderKind) {
        queue.sync {
            if var b = self.buckets[provider] {
                b.consecutiveFailures = (b.consecutiveFailures) + 1
                self.buckets[provider] = b
            }
        }
    }

    private func persistKey(for provider: ProviderKind) -> String {
        return "rl_circuit_until_\(provider.rawValue)"
    }
}

#if DEBUG
extension RateLimitScheduler {
    /// Test-only: Force open the circuit for a provider for a few seconds
    public func _forceOpenCircuit(provider: ProviderKind, seconds: Double) {
        queue.sync {
            if var b = self.buckets[provider] {
                b.circuitOpenUntil = Date().timeIntervalSince1970 + seconds
                self.buckets[provider] = b
                defaults.set(b.circuitOpenUntil, forKey: persistKey(for: provider))
            }
        }
    }

    /// Test-only: Reset scheduler buckets to initial capacities and close circuits
    public func _reset() {
        let now = Date().timeIntervalSince1970
        queue.sync {
            self.buckets = [
                .gemma3: Bucket(
                    rpmCapacity: ProviderRateLimits.gemma3.rpm,
                    tpmCapacity: ProviderRateLimits.gemma3.tpm,
                    rpdCapacity: ProviderRateLimits.gemma3.rpd,
                    rpmTokens: Double(ProviderRateLimits.gemma3.rpm),
                    tpmTokens: Double(ProviderRateLimits.gemma3.tpm),
                    rpdTokens: Double(ProviderRateLimits.gemma3.rpd),
                    lastRefill: now, circuitOpenUntil: 0, consecutiveFailures: 0
                ),
                .gemini: Bucket(
                    rpmCapacity: ProviderRateLimits.gemini.rpm,
                    tpmCapacity: ProviderRateLimits.gemini.tpm,
                    rpdCapacity: ProviderRateLimits.gemini.rpd,
                    rpmTokens: Double(ProviderRateLimits.gemini.rpm),
                    tpmTokens: Double(ProviderRateLimits.gemini.tpm),
                    rpdTokens: Double(ProviderRateLimits.gemini.rpd),
                    lastRefill: now, circuitOpenUntil: 0, consecutiveFailures: 0
                ),
                .googleTranslate: Bucket(
                    rpmCapacity: ProviderRateLimits.googleTranslate.rpm,
                    tpmCapacity: ProviderRateLimits.googleTranslate.tpm,
                    rpdCapacity: ProviderRateLimits.googleTranslate.rpd,
                    rpmTokens: Double(ProviderRateLimits.googleTranslate.rpm),
                    tpmTokens: Double(ProviderRateLimits.googleTranslate.tpm),
                    rpdTokens: Double(ProviderRateLimits.googleTranslate.rpd),
                    lastRefill: now, circuitOpenUntil: 0, consecutiveFailures: 0
                )
            ]
            // Clear persisted circuits
            for provider in ProviderKind.allCases { defaults.removeObject(forKey: persistKey(for: provider)) }
        }
    }

    /// Test-only: Inspect failure count
    public func _consecutiveFailures(provider: ProviderKind) -> Int {
        return queue.sync { self.buckets[provider]?.consecutiveFailures ?? 0 }
    }
}
#endif


