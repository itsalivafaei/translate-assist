//
//  SecretsLoader.swift
//  translate assist
//
//  Phase 0 bootstrap: load API keys from Secrets.plist with env overrides.
//

import Foundation

public struct Secrets {
    public let geminiApiKey: String?
    public let googleTranslateApiKey: String?
    public let gemma3ModelId: String
    public let geminiModelId: String

    public init(geminiApiKey: String?, googleTranslateApiKey: String?, gemma3ModelId: String, geminiModelId: String) {
        self.geminiApiKey = geminiApiKey
        self.googleTranslateApiKey = googleTranslateApiKey
        self.gemma3ModelId = gemma3ModelId
        self.geminiModelId = geminiModelId
    }
}

public enum SecretsLoader {
    public static func load() -> Secrets {
        let envGeminiKey = Env.string("GEMINI_API_KEY")
        let envGTKey = Env.string("GOOGLE_TRANSLATE_API_KEY")
        let envGemmaModel = Env.string("GEMMA3_MODEL_ID", default: "gemma-3-12b") ?? "gemma-3-12b"
        let envGeminiModel = Env.string("GEMINI_MODEL_ID", default: "gemini-2.5-flash-lite") ?? "gemini-2.5-flash-lite"

        let plist = loadPlist()
        let geminiKey = envGeminiKey ?? plist?["GEMINI_API_KEY"] as? String
        let googleKey = envGTKey ?? plist?["GOOGLE_TRANSLATE_API_KEY"] as? String
        let gemmaModel = envGemmaModel
        let geminiModel = envGeminiModel

        return Secrets(
            geminiApiKey: geminiKey?.nilIfEmpty(),
            googleTranslateApiKey: googleKey?.nilIfEmpty(),
            gemma3ModelId: gemmaModel,
            geminiModelId: geminiModel
        )
    }

    private static func loadPlist() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return plist
            }
        } catch {
            // In Phase 0, fail quietly and allow env-only configuration.
        }
        return nil
    }
}

private extension String {
    func nilIfEmpty() -> String? {
        isEmpty ? nil : self
    }
}


