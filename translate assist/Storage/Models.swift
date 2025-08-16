//
//  Models.swift
//  translate assist
//
//  Phase 1: Typed models matching schema v1.
//

import Foundation

public struct Term: Identifiable, Codable {
    public let id: Int64
    public let src: String
    public let dst: String
    public let lemma: String
    public let createdAtIso: String
}

public struct Sense: Identifiable, Codable {
    public let id: Int64
    public let termId: Int64
    public let canonical: String
    public let variants: String?
    public let domain: String?
    public let notes: String?
    public let style: String?
    public let source: String?
    public let confidence: Double?
    public let createdAtIso: String
}

public struct ExampleSentence: Identifiable, Codable {
    public let id: Int64
    public let termId: Int64
    public let srcText: String
    public let dstText: String
    public let provenance: String?
    public let createdAtIso: String
}

public struct ReviewLog: Identifiable, Codable {
    public let id: Int64
    public let termId: Int64
    public let dueAtIso: String
    public let ease: Double
    public let intervalDays: Int
    public let success: Bool
    public let createdAtIso: String
}


