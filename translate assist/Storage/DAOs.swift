//
//  DAOs.swift
//  translate assist
//
//  Phase 1: Basic CRUD for core tables.
//

import Foundation
import SQLite3

public enum TermDAO {
    public static func insert(src: String, dst: String, lemma: String) throws -> Int64 {
        let src = try sanitizeNonEmptyText(field: "src", value: src, maxLen: 8)
        let dst = try sanitizeNonEmptyText(field: "dst", value: dst, maxLen: 8)
        let lemma = try sanitizeNonEmptyText(field: "lemma", value: lemma, maxLen: FieldLimits.lemma)
        let sql = "INSERT INTO term(src, dst, lemma) VALUES(?1, ?2, ?3);"
        var newId: Int64 = 0
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, src, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dst, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, lemma, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert term failed") }
            newId = sqlite3_last_insert_rowid(sqlite3_db_handle(stmt))
        }
        return newId
    }

    public static func fetchByLemma(_ lemma: String, limit: Int = 50, offset: Int = 0) throws -> [Term] {
        let lemma = try sanitizeNonEmptyText(field: "lemma", value: lemma, maxLen: FieldLimits.lemma)
        let limit = max(0, min(limit, 500))
        let offset = max(0, offset)
        let sql = "SELECT id, src, dst, lemma, created_at FROM term WHERE lemma = ?1 ORDER BY id DESC LIMIT \(limit) OFFSET \(offset);"
        return try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, lemma, -1, SQLITE_TRANSIENT)
            var results: [Term] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let src = String(cString: sqlite3_column_text(stmt, 1))
                let dst = String(cString: sqlite3_column_text(stmt, 2))
                let lemma = String(cString: sqlite3_column_text(stmt, 3))
                let created = String(cString: sqlite3_column_text(stmt, 4))
                results.append(Term(id: id, src: src, dst: dst, lemma: lemma, createdAtIso: created))
            }
            return results
        }
    }
}

public enum SenseDAO {
    public static func insert(
        termId: Int64,
        canonical: String,
        variants: String?,
        domain: String?,
        notes: String?,
        style: String?,
        source: String?,
        confidence: Double?
    ) throws -> Int64 {
        let canonical = try sanitizeNonEmptyText(field: "canonical", value: canonical, maxLen: FieldLimits.text)
        let variants = try sanitizeOptionalText(field: "variants", value: variants, maxLen: FieldLimits.text)
        let domain = try sanitizeOptionalText(field: "domain", value: domain, maxLen: FieldLimits.smallText)
        let notes = try sanitizeOptionalText(field: "notes", value: notes, maxLen: FieldLimits.text)
        let style = try sanitizeOptionalText(field: "style", value: style, maxLen: FieldLimits.smallText)
        let source = try sanitizeOptionalText(field: "source", value: source, maxLen: FieldLimits.smallText)
        let sql = "INSERT INTO sense(term_id, canonical, variants, domain, notes, style, source, confidence) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);"
        var newId: Int64 = 0
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, termId)
            sqlite3_bind_text(stmt, 2, canonical, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 3, variants)
            bindOptionalText(stmt, 4, domain)
            bindOptionalText(stmt, 5, notes)
            bindOptionalText(stmt, 6, style)
            bindOptionalText(stmt, 7, source)
            if let confidence { sqlite3_bind_double(stmt, 8, confidence) } else { sqlite3_bind_null(stmt, 8) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert sense failed") }
            newId = sqlite3_last_insert_rowid(sqlite3_db_handle(stmt))
        }
        return newId
    }

    public static func fetchForTerm(_ termId: Int64, limit: Int = 50, offset: Int = 0) throws -> [Sense] {
        let limit = max(0, min(limit, 500))
        let offset = max(0, offset)
        let sql = "SELECT id, term_id, canonical, variants, domain, notes, style, source, confidence, created_at FROM sense WHERE term_id = ?1 ORDER BY id DESC LIMIT \(limit) OFFSET \(offset);"
        return try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, termId)
            var results: [Sense] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let termId = sqlite3_column_int64(stmt, 1)
                let canonical = String(cString: sqlite3_column_text(stmt, 2))
                let variants = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) }
                let domain = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
                let notes = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) }
                let style = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) }
                let source = sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) }
                let confidence = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : Double(sqlite3_column_double(stmt, 8))
                let created = String(cString: sqlite3_column_text(stmt, 9))
                results.append(Sense(id: id, termId: termId, canonical: canonical, variants: variants, domain: domain, notes: notes, style: style, source: source, confidence: confidence, createdAtIso: created))
            }
            return results
        }
    }
}

public enum ExampleDAO {
    public static func insert(termId: Int64, srcText: String, dstText: String, provenance: String?) throws -> Int64 {
        let srcText = try sanitizeNonEmptyText(field: "src_text", value: srcText, maxLen: FieldLimits.text)
        let dstText = try sanitizeNonEmptyText(field: "dst_text", value: dstText, maxLen: FieldLimits.text)
        let provenance = try sanitizeOptionalText(field: "provenance", value: provenance, maxLen: FieldLimits.smallText)
        let sql = "INSERT INTO example(term_id, src_text, dst_text, provenance) VALUES(?1, ?2, ?3, ?4);"
        var newId: Int64 = 0
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, termId)
            sqlite3_bind_text(stmt, 2, srcText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, dstText, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, 4, provenance)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert example failed") }
            newId = sqlite3_last_insert_rowid(sqlite3_db_handle(stmt))
        }
        return newId
    }

    public static func fetchForTerm(_ termId: Int64, limit: Int = 50, offset: Int = 0) throws -> [ExampleSentence] {
        let limit = max(0, min(limit, 500))
        let offset = max(0, offset)
        let sql = "SELECT id, term_id, src_text, dst_text, provenance, created_at FROM example WHERE term_id = ?1 ORDER BY id DESC LIMIT \(limit) OFFSET \(offset);"
        return try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, termId)
            var results: [ExampleSentence] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let termId = sqlite3_column_int64(stmt, 1)
                let srcText = String(cString: sqlite3_column_text(stmt, 2))
                let dstText = String(cString: sqlite3_column_text(stmt, 3))
                let provenance = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
                let created = String(cString: sqlite3_column_text(stmt, 5))
                results.append(ExampleSentence(id: id, termId: termId, srcText: srcText, dstText: dstText, provenance: provenance, createdAtIso: created))
            }
            return results
        }
    }
}

public enum ReviewLogDAO {
    public static func insert(termId: Int64, dueAtIso: String, ease: Double, intervalDays: Int, success: Bool) throws -> Int64 {
        let sql = "INSERT INTO review_log(term_id, due_at, ease, interval, success) VALUES(?1, ?2, ?3, ?4, ?5);"
        var newId: Int64 = 0
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, termId)
            sqlite3_bind_text(stmt, 2, dueAtIso, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, ease)
            sqlite3_bind_int(stmt, 4, Int32(intervalDays))
            sqlite3_bind_int(stmt, 5, success ? 1 : 0)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert review_log failed") }
            newId = sqlite3_last_insert_rowid(sqlite3_db_handle(stmt))
        }
        return newId
    }

    public static func dueBefore(_ iso: String, limit: Int = 50, offset: Int = 0) throws -> [ReviewLog] {
        let limit = max(0, min(limit, 500))
        let offset = max(0, offset)
        let sql = "SELECT id, term_id, due_at, ease, interval, success, created_at FROM review_log WHERE due_at <= ?1 ORDER BY due_at ASC LIMIT \(limit) OFFSET \(offset);"
        return try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, iso, -1, SQLITE_TRANSIENT)
            var results: [ReviewLog] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let termId = sqlite3_column_int64(stmt, 1)
                let dueAt = String(cString: sqlite3_column_text(stmt, 2))
                let ease = Double(sqlite3_column_double(stmt, 3))
                let intervalDays = Int(sqlite3_column_int(stmt, 4))
                let success = sqlite3_column_int(stmt, 5) != 0
                let created = String(cString: sqlite3_column_text(stmt, 6))
                results.append(ReviewLog(id: id, termId: termId, dueAtIso: dueAt, ease: ease, intervalDays: intervalDays, success: success, createdAtIso: created))
            }
            return results
        }
    }
}

// MARK: - Helpers

private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
    if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, index) }
}


