//
//  ExportImport.swift
//  translate assist
//
//  Phase 1: JSONL/CSV export helpers for termbank and examples.
//

import Foundation
import SQLite3

public enum CSVExportService {
    public static func exportSensesCSV(to url: URL) throws {
        let header = ["id","term_id","canonical","variants","domain","notes","style","source","confidence","created_at"].joined(separator: ",")
        var rows: [String] = [header]
        let sql = "SELECT id, term_id, canonical, variants, domain, notes, style, source, confidence, created_at FROM sense ORDER BY id ASC;"
        let csv: String = try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let termId = sqlite3_column_int64(stmt, 1)
                let canonical = String(cString: sqlite3_column_text(stmt, 2))
                let variants = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
                let domain = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                let notes = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""
                let style = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? ""
                let confidence = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? "" : String(sqlite3_column_double(stmt, 8))
                let created = String(cString: sqlite3_column_text(stmt, 9))
                rows.append([
                    String(id), String(termId), canonical, variants, domain, notes, style, source, confidence, created
                ].map { escapeCsv($0) }.joined(separator: ","))
            }
            return rows.joined(separator: "\n")
        }
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public static func exportTermsCSV(to url: URL) throws {
        let header = ["id","src","dst","lemma","created_at"].joined(separator: ",")
        var rows: [String] = [header]
        let sql = "SELECT id, src, dst, lemma, created_at FROM term ORDER BY id ASC;"
        let csv: String = try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let src = String(cString: sqlite3_column_text(stmt, 1))
                let dst = String(cString: sqlite3_column_text(stmt, 2))
                let lemma = String(cString: sqlite3_column_text(stmt, 3))
                let created = String(cString: sqlite3_column_text(stmt, 4))
                rows.append([
                    String(id), src, dst, lemma, created
                ].map { escapeCsv($0) }.joined(separator: ","))
            }
            return rows.joined(separator: "\n")
        }
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public static func exportExamplesCSV(to url: URL) throws {
        let header = ["id","term_id","src_text","dst_text","provenance","created_at"].joined(separator: ",")
        var rows: [String] = [header]
        let sql = "SELECT id, term_id, src_text, dst_text, provenance, created_at FROM example ORDER BY id ASC;"
        let csv: String = try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let termId = sqlite3_column_int64(stmt, 1)
                let srcText = String(cString: sqlite3_column_text(stmt, 2))
                let dstText = String(cString: sqlite3_column_text(stmt, 3))
                let provenance = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
                let created = String(cString: sqlite3_column_text(stmt, 5))
                rows.append([
                    String(id), String(termId), srcText, dstText, provenance, created
                ].map { escapeCsv($0) }.joined(separator: ","))
            }
            return rows.joined(separator: "\n")
        }
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func escapeCsv(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

public enum JSONLExportService {
    public static func exportTermbankJSONL(to url: URL) throws {
        let sql = "SELECT t.id, t.src, t.dst, t.lemma, t.created_at FROM term t ORDER BY t.id ASC;"
        let handle = try FileHandle(forWritingTo: preparedFile(at: url))
        defer { try? handle.close() }
        try DatabaseManager.shared.withPreparedStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let termId = sqlite3_column_int64(stmt, 0)
                let src = String(cString: sqlite3_column_text(stmt, 1))
                let dst = String(cString: sqlite3_column_text(stmt, 2))
                let lemma = String(cString: sqlite3_column_text(stmt, 3))
                let created = String(cString: sqlite3_column_text(stmt, 4))
                let senses = try? SenseDAO.fetchForTerm(termId)
                let examples = try? ExampleDAO.fetchForTerm(termId)
                let payload: [String: Any] = [
                    "term": ["id": termId, "src": src, "dst": dst, "lemma": lemma, "created_at": created],
                    "senses": senses?.map(encodableToDict) ?? [],
                    "examples": examples?.map(encodableToDict) ?? []
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                handle.write(data)
                handle.write("\n".data(using: .utf8)!)
            }
        }
    }

    private static func preparedFile(at url: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        fm.createFile(atPath: url.path, contents: nil)
        return url
    }

    private static func encodableToDict<T: Encodable>(_ value: T) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try? encoder.encode(value)
        if let data, let obj = try? JSONSerialization.jsonObject(with: data, options: []), let dict = obj as? [String: Any] {
            return dict
        }
        return [:]
    }
}

public enum ImportService {
    // Import JSONL of the shape produced by JSONLExportService.exportTermbankJSONL
    public static func importTermbankJSONL(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8), options: []) as? [String: Any] else { continue }
            guard let termObj = obj["term"] as? [String: Any] else { continue }
            let src = (termObj["src"] as? String) ?? "en"
            let dst = (termObj["dst"] as? String) ?? "fa"
            let lemma = (termObj["lemma"] as? String) ?? ""
            if lemma.isEmpty { continue }
            let termId = try TermDAO.insert(src: src, dst: dst, lemma: lemma)
            if let senses = obj["senses"] as? [[String: Any]] {
                for s in senses {
                    _ = try? SenseDAO.insert(
                        termId: termId,
                        canonical: (s["canonical"] as? String) ?? "",
                        variants: s["variants"] as? String,
                        domain: s["domain"] as? String,
                        notes: s["notes"] as? String,
                        style: s["style"] as? String,
                        source: s["source"] as? String,
                        confidence: s["confidence"] as? Double
                    )
                }
            }
            if let examples = obj["examples"] as? [[String: Any]] {
                for e in examples {
                    if let srcText = e["srcText"] as? String, let dstText = e["dstText"] as? String {
                        _ = try? ExampleDAO.insert(termId: termId, srcText: srcText, dstText: dstText, provenance: e["provenance"] as? String)
                    }
                }
            }
        }
    }

    // Import senses from CSV produced by CSVExportService.exportSensesCSV
    public static func importSensesCSV(from url: URL, termIdMapper: (String) -> Int64?) throws {
        let data = try Data(contentsOf: url)
        guard var content = String(data: data, encoding: .utf8) else { return }
        // Remove BOM if present
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        let rows = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard !rows.isEmpty else { return }
        // Skip header
        for row in rows.dropFirst() {
            let parts = parseCsvRow(String(row))
            guard parts.count >= 10 else { continue }
            let termIdStr = parts[1]
            guard let termId = termIdMapper(termIdStr) ?? Int64(termIdStr) else { continue }
            let canonical = parts[2]
            let variants = emptyToNil(parts[3])
            let domain = emptyToNil(parts[4])
            let notes = emptyToNil(parts[5])
            let style = emptyToNil(parts[6])
            let source = emptyToNil(parts[7])
            let confidence = Double(parts[8])
            _ = try? SenseDAO.insert(
                termId: termId,
                canonical: canonical,
                variants: variants,
                domain: domain,
                notes: notes,
                style: style,
                source: source,
                confidence: confidence
            )
        }
    }

    private static func parseCsvRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = row.makeIterator()
        while let ch = iterator.next() {
            if ch == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else if next == "," { result.append(current); current = ""; inQuotes = false } else { current.append(next) }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


