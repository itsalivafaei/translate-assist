//
//  Metrics.swift
//  translate assist
//
//  Phase 11: DB-backed metrics provider and DAO.
//

import Foundation
import SQLite3

public enum MetricsDAO {
    @discardableResult
    public static func insert(event: String, value: Double?) throws -> Int64 {
        let sql = "INSERT INTO metrics(event, value) VALUES(?1, ?2);"
        var newId: Int64 = 0
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, event, -1, SQLITE_TRANSIENT)
            if let v = value {
                sqlite3_bind_double(stmt, 2, v)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.execute(message: "insert metrics failed") }
            newId = sqlite3_last_insert_rowid(sqlite3_db_handle(stmt))
        }
        return newId
    }
}

public final class DBMetricsProvider: MetricsProvider {
    public init() {}
    public func track(event: String, value: Double?) {
        // Best-effort; do not crash on failures
        do { _ = try MetricsDAO.insert(event: event, value: value) } catch { /* swallow */ }
    }
}


