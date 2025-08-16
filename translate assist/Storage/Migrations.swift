//
//  Migrations.swift
//  translate assist
//
//  Phase 1: Deterministic schema v1 migrations.
//

import Foundation
import SQLite3

enum Migrations {
    static func applyAll(on db: DatabaseManager) throws {
        try db.execute("PRAGMA journal_mode=WAL;")
        try db.execute("CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY);")
        let current = try currentVersion(on: db)
        if current < 1 {
            try v1(on: db)
            try record(version: 1, on: db)
        }
        if current < 2 {
            try v2(on: db)
            try record(version: 2, on: db)
        }
    }

    private static func currentVersion(on db: DatabaseManager) throws -> Int {
        let version: Int? = try db.withPreparedStatement("SELECT MAX(version) FROM schema_migrations") { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return nil
        }
        return version ?? 0
    }

    private static func record(version: Int, on db: DatabaseManager) throws {
        try db.execute("INSERT INTO schema_migrations(version) VALUES(\(version));")
    }

    // Schema v1 per planning_v_1.md
    private static func v1(on db: DatabaseManager) throws {
        // meta
        try db.execute("""
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)

        // term
        try db.execute("""
        CREATE TABLE IF NOT EXISTS term (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            src TEXT NOT NULL,
            dst TEXT NOT NULL,
            lemma TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE INDEX IF NOT EXISTS idx_term_lemma ON term(lemma);
        """)

        // sense
        try db.execute("""
        CREATE TABLE IF NOT EXISTS sense (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term_id INTEGER NOT NULL REFERENCES term(id) ON DELETE CASCADE,
            canonical TEXT NOT NULL,
            variants TEXT,
            domain TEXT,
            notes TEXT,
            style TEXT,
            source TEXT,
            confidence REAL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE INDEX IF NOT EXISTS idx_sense_term ON sense(term_id);
        """)

        // example
        try db.execute("""
        CREATE TABLE IF NOT EXISTS example (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term_id INTEGER NOT NULL REFERENCES term(id) ON DELETE CASCADE,
            src_text TEXT NOT NULL,
            dst_text TEXT NOT NULL,
            provenance TEXT,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE INDEX IF NOT EXISTS idx_example_term ON example(term_id);
        """)

        // review_log
        try db.execute("""
        CREATE TABLE IF NOT EXISTS review_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term_id INTEGER NOT NULL REFERENCES term(id) ON DELETE CASCADE,
            due_at TEXT NOT NULL,
            ease REAL NOT NULL,
            interval INTEGER NOT NULL,
            success INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE INDEX IF NOT EXISTS idx_review_term ON review_log(term_id);
        CREATE INDEX IF NOT EXISTS idx_review_due ON review_log(due_at);
        """)

        // caches
        try db.execute("""
        CREATE TABLE IF NOT EXISTS cache_mt (
            key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now')),
            ttl INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS cache_llm (
            key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now')),
            ttl INTEGER NOT NULL
        );
        """)

        // metrics
        try db.execute("""
        CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event TEXT NOT NULL,
            value REAL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE INDEX IF NOT EXISTS idx_metrics_event ON metrics(event);
        """)
    }

    // Schema v2: input history for last N entries (distinct by text), Phase 9
    private static func v2(on db: DatabaseManager) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS input_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE INDEX IF NOT EXISTS idx_input_history_created ON input_history(created_at DESC);
        """)
    }
}


