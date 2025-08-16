//
//  TatoebaExamplesProvider.swift
//  translate assist
//
//  Phase 6: Tatoeba-based examples provider using public API v0.
//  Best-effort language mapping; returns up to 3 examples with provenance labels.
//

import Foundation

public final class TatoebaExamplesProvider: ExamplesProvider {
    public init() {}

    public func search(term: String, src: String, dst: String, context: String?) async throws -> [Example] {
        guard let url = buildURL(term: term, src: src, dst: dst) else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let resp = try await NetworkClient.shared.send(req)
        let json = try JSONSerialization.jsonObject(with: resp.data, options: [])
        guard let dict = json as? [String: Any] else { return [] }
        let results = dict["results"] as? [[String: Any]] ?? []
        var examples: [Example] = []
        for item in results {
            guard let srcText = item["text"] as? String else { continue }
            if let translations = item["translations"] as? [[String: Any]] {
                for t in translations {
                    if let lang = t["lang"] as? String, isTarget(lang, dst: dst), let dstText = t["text"] as? String {
                        examples.append(Example(srcText: srcText, dstText: dstText, provenance: "tatoeba"))
                        if examples.count >= 3 { break }
                    }
                }
            }
            if examples.count >= 3 { break }
        }
        return examples
    }

    private func buildURL(term: String, src: String, dst: String) -> URL? {
        let base = "https://tatoeba.org/en/api_v0/search"
        var comps = URLComponents(string: base)
        let from = mapLang(src)
        let to = mapLang(dst)
        comps?.queryItems = [
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "size", value: "5")
        ]
        return comps?.url
    }

    private func isTarget(_ tatoebaLang: String, dst: String) -> Bool {
        return mapLang(dst) == tatoebaLang.lowercased()
    }

    private func mapLang(_ code: String) -> String {
        switch code.lowercased() {
        case "en": return "eng"
        case "es": return "spa"
        case "zh": return "cmn" // Mandarin Chinese
        case "hi": return "hin"
        case "ar": return "ara"
        case "fa": return "fas"
        default: return code.lowercased()
        }
    }
}


