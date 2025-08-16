//
//  Constants.swift
//  translate assist
//
//  Phase 0 bootstrap: global constants and env helpers.
//

import Foundation

public enum Env {
    public static func string(_ key: String, default defaultValue: String? = nil) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return value ?? defaultValue
    }

    public static func int(_ key: String, default defaultValue: Int) -> Int {
        if let raw = ProcessInfo.processInfo.environment[key], let value = Int(raw) {
            return value
        }
        return defaultValue
    }

    public static func double(_ key: String, default defaultValue: Double) -> Double {
        if let raw = ProcessInfo.processInfo.environment[key], let value = Double(raw) {
            return value
        }
        return defaultValue
    }
}

public enum Constants {
    // Networking
    public static let requestTimeoutMs: Int = Env.int("REQUEST_TIMEOUT_MS", default: 7000)

    // UI
    public static let popoverWidth: Double = 360
    public static let popoverHeight: Double = 420

    // Scheduler
    public static let schedulerBurstSize: Int = Env.int("SCHEDULER_BURST_SIZE", default: 2)
    public static let circuitBreakerCooldownMs: Int = Env.int("CIRCUIT_BREAKER_COOLDOWN_MS", default: 60_000)

    // Cache TTLs
    public static let cacheMTTtlSeconds: Int = Env.int("CACHE_MT_TTL_S", default: 86_400) // 24h
    public static let cacheLLMTtlSeconds: Int = Env.int("CACHE_LLM_TTL_S", default: 86_400) // 24h

    // Cache maintenance interval (minutes)
    public static let cacheMaintenanceIntervalMinutes: Int = Env.int("CACHE_MAINTENANCE_MIN", default: 30)

    // Feature flag: enforce TTL on cache reads (default disabled in Debug/tests, enabled in Release)
    public static let cacheEnforceTtlOnReads: Bool = {
        #if DEBUG
        return Env.int("CACHE_ENFORCE_TTL_ON_READS", default: 0) == 1
        #else
        return Env.int("CACHE_ENFORCE_TTL_ON_READS", default: 1) == 1
        #endif
    }()
}


