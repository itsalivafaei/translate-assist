//
//  RateLimitConfig.swift
//  translate assist
//
//  Phase 0 bootstrap: model/provider quotas (env-overridable).
//

import Foundation

public struct RateLimitConfig {
    public let rpm: Int
    public let tpm: Int
    public let rpd: Int

    public init(rpm: Int, tpm: Int, rpd: Int) {
        self.rpm = rpm
        self.tpm = tpm
        self.rpd = rpd
    }
}

public enum ProviderRateLimits {
    // Defaults per planning_v_1.md (tunable via env).
    public static let gemma3 = RateLimitConfig(
        rpm: Env.int("GEMMA3_RPM", default: 30),
        tpm: Env.int("GEMMA3_TPM", default: 15_000),
        rpd: Env.int("GEMMA3_RPD", default: 14_400)
    )

    public static let gemini = RateLimitConfig(
        rpm: Env.int("GEMINI_RPM", default: 30),
        tpm: Env.int("GEMINI_TPM", default: 6_000),
        rpd: Env.int("GEMINI_RPD", default: 14_400)
    )

    public static let googleTranslate = RateLimitConfig(
        rpm: Env.int("GOOGLE_TRANSLATE_RPM", default: 30),
        tpm: Env.int("GOOGLE_TRANSLATE_CPM", default: 100_000), // characters per minute proxy
        rpd: Env.int("GOOGLE_TRANSLATE_CPD", default: 50_000)
    )
}


