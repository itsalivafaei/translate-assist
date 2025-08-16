//
//  CacheService.swift
//  translate assist
//
//  Phase 4: MT/LLM caches backed by SQLite with TTL and eviction.
//

import Foundation
import SQLite3
import CryptoKit

public enum CacheService {
    // MARK: - Public API (MT)

    public static func makeMTKey(term: String, src: String, dst: String = "fa", context: String?) -> String {
        let normalizedTerm = normalizeForKey(term)
        let normalizedSrc = normalizeForKey(src)
        let normalizedDst = normalizeForKey(dst)
        let contextHash = context.map { sha256Hex(of: $0) } ?? "none"
        let base = "v1|mt|src:\(normalizedSrc)|dst:\(normalizedDst)|term:\(normalizedTerm)|ctx:\(contextHash)"
        return sha256Hex(of: base)
    }

    public static func getMT(forKey key: String) throws -> MTResponse? {
        let sql: String
        if Constants.cacheEnforceTtlOnReads {
            sql = """
            SELECT payload FROM cache_mt
            WHERE key = ?1
              AND ((CASE WHEN length(created_at) > 10 THEN strftime('%s', created_at) ELSE CAST(created_at AS INTEGER) END) + ttl) > strftime('%s','now')
            LIMIT 1;
            """
        } else {
            sql = "SELECT payload FROM cache_mt WHERE key = ?1 LIMIT 1;"
        }
        return try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
                let json = String(cString: cString)
                let data = Data(json.utf8)
                return try? JSONDecoder().decode(MTResponse.self, from: data)
            }
            return nil
        }
    }

    public static func putMT(forKey key: String, value: MTResponse, ttlSeconds: Int = Constants.cacheMTTtlSeconds) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let json = String(decoding: data, as: UTF8.self)
        let sql = """
        INSERT INTO cache_mt(key, payload, ttl, created_at) VALUES(?1, ?2, ?3, STRFTIME('%s','now'))
        ON CONFLICT(key) DO UPDATE SET
            payload = excluded.payload,
            ttl = excluded.ttl,
            created_at = STRFTIME('%s','now');
        """
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, json, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(ttlSeconds))
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert/update cache_mt failed") }
        }
    }

    // MARK: - Public API (LLM)

    public static func makeLLMKey(term: String, src: String, dst: String = "fa", context: String?, persona: String?, mt: MTResponse) -> String {
        let normalizedTerm = normalizeForKey(term)
        let normalizedSrc = normalizeForKey(src)
        let normalizedDst = normalizeForKey(dst)
        let contextHash = context.map { sha256Hex(of: $0) } ?? "none"
        let personaHash = persona.map { sha256Hex(of: $0) } ?? "none"
        let mtHash = hashMTResponse(mt)
        let base = "v1|llm|src:\(normalizedSrc)|dst:\(normalizedDst)|term:\(normalizedTerm)|ctx:\(contextHash)|persona:\(personaHash)|mt:\(mtHash)"
        return sha256Hex(of: base)
    }

    public static func getLLM(forKey key: String) throws -> LLMDecision? {
        let sql: String
        if Constants.cacheEnforceTtlOnReads {
            sql = """
            SELECT payload FROM cache_llm
            WHERE key = ?1
              AND ((CASE WHEN length(created_at) > 10 THEN strftime('%s', created_at) ELSE CAST(created_at AS INTEGER) END) + ttl) > strftime('%s','now')
            LIMIT 1;
            """
        } else {
            sql = "SELECT payload FROM cache_llm WHERE key = ?1 LIMIT 1;"
        }
        return try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
                let json = String(cString: cString)
                let data = Data(json.utf8)
                return try? JSONDecoder().decode(LLMDecision.self, from: data)
            }
            return nil
        }
    }

    public static func putLLM(forKey key: String, value: LLMDecision, ttlSeconds: Int = Constants.cacheLLMTtlSeconds) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let json = String(decoding: data, as: UTF8.self)
        let sql = """
        INSERT INTO cache_llm(key, payload, ttl, created_at) VALUES(?1, ?2, ?3, STRFTIME('%s','now'))
        ON CONFLICT(key) DO UPDATE SET
            payload = excluded.payload,
            ttl = excluded.ttl,
            created_at = STRFTIME('%s','now');
        """
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, json, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(ttlSeconds))
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert/update cache_llm failed") }
        }
    }

    // MARK: - Maintenance

    public static func evictExpired() throws {
        try DatabaseManager.shared.execute("DELETE FROM cache_mt WHERE ((CASE WHEN length(created_at) > 10 THEN strftime('%s', created_at) ELSE CAST(created_at AS INTEGER) END) + ttl) <= strftime('%s','now');")
        try DatabaseManager.shared.execute("DELETE FROM cache_llm WHERE ((CASE WHEN length(created_at) > 10 THEN strftime('%s', created_at) ELSE CAST(created_at AS INTEGER) END) + ttl) <= strftime('%s','now');")
    }

    // Optional helper to cap size by removing oldest beyond a soft limit
    public static func pruneIfOversized(maxEntriesPerTable: Int = 10_000) throws {
        try DatabaseManager.shared.execute("""
        DELETE FROM cache_mt WHERE key IN (
            SELECT key FROM cache_mt ORDER BY created_at ASC LIMIT (SELECT MAX(0, COUNT(*) - \(maxEntriesPerTable)) FROM cache_mt)
        );
        """
        )
        try DatabaseManager.shared.execute("""
        DELETE FROM cache_llm WHERE key IN (
            SELECT key FROM cache_llm ORDER BY created_at ASC LIMIT (SELECT MAX(0, COUNT(*) - \(maxEntriesPerTable)) FROM cache_llm)
        );
        """
        )
    }

    // MARK: - Internals

    private static func normalizeForKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sha256Hex(of text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func hashMTResponse(_ mt: MTResponse) -> String {
        // Intentionally exclude usage quotas from hash to avoid cache churn
        // when provider returns varying quota snapshots. Include detectedSrc and
        // full candidate tuple fields for stability.
        let parts: [String] = [
            mt.detectedSrc ?? "",
            mt.candidates.map { [$0.text, $0.pos ?? "", $0.ipa ?? "", $0.provenance].joined(separator: "\u{1F}") }.joined(separator: "\u{1E}")
        ]
        return sha256Hex(of: parts.joined(separator: "\u{1D}"))
    }

    // Build LLM cache key directly from decision input (uses candidates only)
    public static func makeLLMKeyFromInput(term: String, src: String, dst: String = "fa", context: String?, persona: String?, inputCandidates: [SenseCandidate], providerTag: String = "primary") -> String {
        let normalizedTerm = normalizeForKey(term)
        let normalizedSrc = normalizeForKey(src)
        let normalizedDst = normalizeForKey(dst)
        let contextHash = context.map { sha256Hex(of: $0) } ?? "none"
        let personaHash = persona.map { sha256Hex(of: $0) } ?? "none"
        let mtHash = hashCandidates(inputCandidates)
        let base = "v1|llm|src:\(normalizedSrc)|dst:\(normalizedDst)|term:\(normalizedTerm)|ctx:\(contextHash)|persona:\(personaHash)|mt:\(mtHash)|tag:\(providerTag)"
        return sha256Hex(of: base)
    }

    private static func hashCandidates(_ candidates: [SenseCandidate]) -> String {
        let joined = candidates.map { [$0.text, $0.pos ?? "", $0.ipa ?? "", $0.provenance].joined(separator: "\u{1F}") }.joined(separator: "\u{1E}")
        return sha256Hex(of: joined)
    }
}


