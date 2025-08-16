//
//  SQLiteHelpers.swift
//  translate assist
//
//  Phase 1: Helpers and shims for SQLite C API interop.
//

import Foundation
import SQLite3

// Swift shim for SQLITE_TRANSIENT to pass ownership correctly for bound text.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


