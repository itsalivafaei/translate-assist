//
//  DatabaseManager.swift
//  translate assist
//
//  Phase 1: SQLite stack, deterministic migrations, monthly vacuum.
//

import Foundation
import SQLite3

public final class DatabaseManager {
    public static let shared = DatabaseManager()

    private let queue = DispatchQueue(label: "com.translateassist.db.queue")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var db: OpaquePointer?

    private init() {
        queue.setSpecific(key: queueKey, value: 1)
    }

    public func start() {
        // Important: do not call queue.sync from here to avoid re-entrant deadlocks.
        // Startup runs on the caller's thread; inner DB calls are queued as needed.
        do {
            try open()
            try enableForeignKeys()
            try Migrations.applyAll(on: self)
            // Phase 4: Evict expired cache entries at startup
            try CacheService.evictExpired()
            try runMonthlyVacuumIfNeeded()
        } catch {
            // For Phase 1, fail silently but keep app usable.
        }
    }

    deinit {
        close()
    }

    private func open() throws {
        let url = try databaseURL()
        let path = url.path
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &connection, flags, nil) != SQLITE_OK {
            throw DatabaseError.open(message: lastErrorMessage(db: connection))
        }
        db = connection
    }

    private func enableForeignKeys() throws {
        try execute("PRAGMA foreign_keys = ON;")
    }

    private func databaseURL() throws -> URL {
        let fm = FileManager.default
        let baseDir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let appDir = baseDir.appendingPathComponent("translate_assist", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) {
            try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir.appendingPathComponent("db.sqlite3")
    }

    private func close() {
        if let connection = db {
            sqlite3_close(connection)
            db = nil
        }
    }

    public func execute(_ sql: String) throws {
        let work = {
            () throws -> Void in
            guard let connection = self.db else { throw DatabaseError.notOpen }
            var errorMessagePointer: UnsafeMutablePointer<Int8>?
            if sqlite3_exec(connection, sql, nil, nil, &errorMessagePointer) != SQLITE_OK {
                let message = errorMessagePointer.flatMap { String(cString: $0) } ?? self.lastErrorMessage(db: connection)
                if let errorMessagePointer { sqlite3_free(errorMessagePointer) }
                throw DatabaseError.execute(message: message)
            }
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            try work()
        } else {
            try queue.sync(execute: work)
        }
    }

    public func withPreparedStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            guard let connection = db else { throw DatabaseError.notOpen }
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(connection, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepare(message: lastErrorMessage(db: connection))
            }
            defer { sqlite3_finalize(statement) }
            guard let statement else { throw DatabaseError.prepare(message: "nil statement") }
            return try body(statement)
        } else {
            return try queue.sync {
                guard let connection = db else { throw DatabaseError.notOpen }
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(connection, sql, -1, &statement, nil) != SQLITE_OK {
                    throw DatabaseError.prepare(message: lastErrorMessage(db: connection))
                }
                defer { sqlite3_finalize(statement) }
                guard let statement else { throw DatabaseError.prepare(message: "nil statement") }
                return try body(statement)
            }
        }
    }

    private func runMonthlyVacuumIfNeeded() throws {
        let lastVacuumIso = try getMeta(key: "last_vacuum_at")
        let now = Date()
        let shouldVacuum: Bool
        if let lastVacuumIso, let lastVacuum = ISO8601DateFormatter().date(from: lastVacuumIso) {
            let days = now.timeIntervalSince(lastVacuum) / (60 * 60 * 24)
            shouldVacuum = days >= 30
        } else {
            shouldVacuum = true
        }
        if shouldVacuum {
            try execute("VACUUM;")
            let iso = ISO8601DateFormatter().string(from: now)
            try setMeta(key: "last_vacuum_at", value: iso)
            #if DEBUG
            print("[DB] VACUUM completed at=\(iso)")
            #endif
        }
    }

    // MARK: - Meta helpers

    public func getMeta(key: String) throws -> String? {
        try withPreparedStatement("SELECT value FROM meta WHERE key = ?1 LIMIT 1") { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    return String(cString: cString)
                }
            }
            return nil
        }
    }

    public func setMeta(key: String, value: String) throws {
        try execute("INSERT INTO meta(key, value) VALUES('\(escapeSingleQuotes(key))', '\(escapeSingleQuotes(value))') ON CONFLICT(key) DO UPDATE SET value=excluded.value;")
    }

    // MARK: - Utilities

    private func escapeSingleQuotes(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    private func lastErrorMessage(db: OpaquePointer?) -> String {
        if let db { return String(cString: sqlite3_errmsg(db)) }
        return "Unknown database error"
    }
}

public enum DatabaseError: Error {
    case notOpen
    case open(message: String)
    case execute(message: String)
    case prepare(message: String)
}



