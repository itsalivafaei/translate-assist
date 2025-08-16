//
//  Validation.swift
//  translate assist
//
//  Phase 1: Input validation and sanitization helpers.
//

import Foundation

public enum ValidationError: Error, LocalizedError {
    case emptyField(field: String)
    case tooLong(field: String, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "\(field) must not be empty"
        case .tooLong(let field, let limit):
            return "\(field) exceeds max length \(limit)"
        }
    }
}

public enum FieldLimits {
    public static let lemma = 512
    public static let text = 2048
    public static let smallText = 512
}

@inline(__always)
public func sanitizeNonEmptyText(field: String, value: String, maxLen: Int) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ValidationError.emptyField(field: field) }
    if trimmed.count > maxLen {
        throw ValidationError.tooLong(field: field, limit: maxLen)
    }
    return trimmed
}

@inline(__always)
public func sanitizeOptionalText(field: String, value: String?, maxLen: Int) throws -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count > maxLen {
        throw ValidationError.tooLong(field: field, limit: maxLen)
    }
    return trimmed
}


