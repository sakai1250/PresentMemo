import Foundation
#if canImport(Translation)
import Translation
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

actor TranslationService {
    static let shared = TranslationService()

    private var cache: [String: String] = [:]
    private var csvDictionary: [String: String]?
    private enum SupportState { case unknown, supported, unsupported }
    private var supportState: SupportState = .unknown

    private init() {}

    /// ai_specialized_terms.csv から英日辞書を読み込む
    private func loadCSVDictionary() -> [String: String] {
        if let dict = csvDictionary { return dict }

        var dict: [String: String] = [:]
        guard let url = Bundle.main.url(forResource: "ai_specialized_terms", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            csvDictionary = dict
            return dict
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.lowercased() != "english,japanese" else { continue }

            // Handle quoted CSV fields
            let parts: [String]
            if trimmed.contains("\"") {
                parts = parseCSVLine(trimmed)
            } else {
                parts = trimmed.components(separatedBy: ",")
            }
            guard parts.count >= 2 else { continue }

            let english = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let japanese = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, !japanese.isEmpty else { continue }

            // 最初の訳語（" / " で区切られている場合）を使用
            let primaryJapanese = japanese.components(separatedBy: " / ").first ?? japanese
            dict[english.lowercased()] = primaryJapanese
        }

        csvDictionary = dict
        return dict
    }

    /// Handle CSV lines with quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    func translateTermToJapanese(_ term: String) async -> String? {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        if containsJapanese(key) {
            return key
        }

        if let cached = cache[key.lowercased()] {
            return cached
        }

        // ユーザー辞書を最優先で参照
        let userDict = GlossaryManager.shared.dictionary()
        if let userHit = userDict[key.lowercased()] {
            cache[key.lowercased()] = userHit
            return userHit
        }

        // バンドルCSV辞書を参照
        let dict = loadCSVDictionary()
        if let csvHit = dict[key.lowercased()] {
            cache[key.lowercased()] = csvHit
            return csvHit
        }

        if let apple = await translateWithAppleTranslationIfAvailable(key) {
            cache[key.lowercased()] = apple
            return apple
        }

        if let fm = await translateWithFoundationModelsIfAvailable(key) {
            cache[key.lowercased()] = fm
            return fm
        }

        if let web = await translateWithFreeWebAPI(key) {
            cache[key.lowercased()] = web
            return web
        }

        if let composed = composeTranslationFromDictionaries(key, userDict: userDict, csvDict: dict) {
            cache[key.lowercased()] = composed
            return composed
        }

        return nil
    }

    private func translateWithAppleTranslationIfAvailable(_ text: String) async -> String? {
        #if canImport(Translation)
        if #available(iOS 26.4, *) {
            let supported = await ensureSupport()
            guard supported else { return nil }

            let source = Locale.Language(identifier: "en")
            let target = Locale.Language(identifier: "ja")
            do {
                let session = TranslationSession(installedSource: source, target: target)
                let response = try await session.translate(text)
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleanedTranslationCandidate(translated, original: text)
            } catch {
                supportState = .unsupported
                return nil
            }
        }
        #endif

        return nil
    }

    private func translateWithFoundationModelsIfAvailable(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return nil }
            let session = LanguageModelSession()
            let prompt = """
Translate this English technical term into concise natural Japanese.
Return Japanese only. No explanations.
Text: \(text)
"""
            do {
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.0)
                )
                let translated = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                return cleanedTranslationCandidate(translated, original: text)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    private func translateWithFreeWebAPI(_ text: String) async -> String? {
        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|ja")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return nil
            }
            let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            let translated = decoded.responseData.translatedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanedTranslationCandidate(translated, original: text)
        } catch {
            return nil
        }
    }

    #if canImport(Translation)
    @available(iOS 26.4, *)
    private func ensureSupport() async -> Bool {
        switch supportState {
        case .supported: return true
        case .unsupported: return false
        case .unknown:
            let source = Locale.Language(identifier: "en")
            let target = Locale.Language(identifier: "ja")
            let availability = LanguageAvailability(preferredStrategy: .lowLatency)
            let status = await availability.status(from: source, to: target)
            switch status {
            case .installed, .supported:
                supportState = .supported
                return true
            case .unsupported:
                supportState = .unsupported
                return false
            @unknown default:
                supportState = .unsupported
                return false
            }
        }
    }
    #endif

    private func cleanedTranslationCandidate(_ candidate: String, original: String) -> String? {
        let cleaned = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        guard !cleaned.isEmpty else { return nil }

        // Reject obvious non-translations (English copied back as-is).
        if !containsJapanese(cleaned), cleaned.lowercased() == original.lowercased() {
            return nil
        }
        return cleaned
    }

    private func composeTranslationFromDictionaries(
        _ text: String,
        userDict: [String: String],
        csvDict: [String: String]
    ) -> String? {
        let separators = CharacterSet(charactersIn: " -_/()")
        let tokens = text
            .split(whereSeparator: { scalar in
                scalar.unicodeScalars.allSatisfy { separators.contains($0) }
            })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard tokens.count >= 2 else { return nil }

        var mapped: [String] = []
        var translatedCount = 0
        for token in tokens {
            let lower = token.lowercased()
            if let hit = userDict[lower] ?? csvDict[lower] {
                mapped.append(hit)
                translatedCount += 1
            } else if token.allSatisfy({ $0.isUppercase || $0.isNumber }) {
                mapped.append(token)
            } else {
                mapped.append(token)
            }
        }

        guard translatedCount > 0 else { return nil }
        return mapped.joined(separator: "・")
    }

    private func containsJapanese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF:
                return true
            default:
                continue
            }
        }
        return false
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData

    struct ResponseData: Decodable {
        let translatedText: String
    }
}
