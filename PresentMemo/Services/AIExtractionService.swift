import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AIExtractionService {
    static let shared = AIExtractionService()

    enum Domain {
        case general
        case presentation
    }

    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "ai.enabled")
    }

    var canUseAI: Bool {
        guard isEnabled else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                return true
            }
        }
        #endif
        return false
    }

    func extractTermContextPairs(
        from text: String,
        max: Int = 80,
        domain: Domain = .general
    ) async -> [(term: String, context: String)] {
        guard canUseAI else { return [] }

        let normalizedSource = normalizeSource(text)
        guard !normalizedSource.isEmpty else { return [] }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await requestFoundationModels(sourceText: normalizedSource, max: max, domain: domain)
        }
        #endif

        return []
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func requestFoundationModels(
        sourceText: String,
        max: Int,
        domain: Domain
    ) async -> [(term: String, context: String)] {
        let prompt = makePrompt(content: String(sourceText.prefix(18000)), max: max, domain: domain)
        let options = GenerationOptions(temperature: 0.1)
        let session = LanguageModelSession()

        do {
            let response = try await session.respond(to: prompt, options: options)
            return parseModelText(response.content, sourceText: sourceText, max: max)
        } catch {
            return []
        }
    }
    #endif

    private func makePrompt(content: String, max: Int, domain: Domain) -> String {
        switch domain {
        case .general:
            return """
Extract important technical terms from the following content.
Return ONLY a JSON array.
Each item must be an object with keys: "term", "context".
Constraints:
- Max items: \(max)
- term: concise phrase (1-6 words)
- context: short explanation from the BODY text only (max 160 chars)
- Use only terms that literally appear in the content
- No duplicates
- Avoid generic words
- Do not use author names, affiliations, company names, emails, URLs, references, or copyright lines for context.

Content:
\(content)
"""
        case .presentation:
            return """
You are extracting memorization keywords from scientific presentation slides.
Return ONLY a JSON array of objects: {"term":"...","context":"..."}.
Hard constraints:
- Max items: \(max)
- Use only terms that literally appear in the provided text.
- Prioritize: methods, models, datasets, metrics, tasks, abbreviations, key findings.
- Exclude generic words (introduction, result, conclusion, overview, etc.).
- term length: 1-6 words.
- context: short explanation from nearby BODY text (max 160 chars).
- Never use author lists, affiliations, company names, URLs, emails, references, or copyright lines.

Slide text:
\(content)
"""
        }
    }

    private func parseModelText(_ modelText: String, sourceText: String, max: Int) -> [(term: String, context: String)] {
        let jsonText = extractJSONArray(from: modelText) ?? modelText
        guard let jsonData = jsonText.data(using: .utf8) else { return [] }

        if let items = try? JSONDecoder().decode([TermContextItem].self, from: jsonData) {
            return normalize(items: items, sourceText: sourceText, max: max)
        }

        if let dictItems = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            let mapped = dictItems.compactMap { dict -> TermContextItem? in
                guard let term = dict["term"] as? String else { return nil }
                let context = (dict["context"] as? String) ?? term
                return TermContextItem(term: term, context: context)
            }
            return normalize(items: mapped, sourceText: sourceText, max: max)
        }

        return []
    }

    private func normalize(items: [TermContextItem], sourceText: String, max: Int) -> [(term: String, context: String)] {
        let lowerSource = sourceText.lowercased()

        var seen: Set<String> = []
        var result: [(term: String, context: String)] = []

        for item in items {
            let term = clean(item.term)
            guard isGoodTerm(term) else { continue }

            let lowerTerm = term.lowercased()
            guard lowerSource.contains(lowerTerm) else { continue }
            guard !seen.contains(lowerTerm) else { continue }

            seen.insert(lowerTerm)
            let modelContext = clean(item.context)
            let safeModelContext = isAcceptableContext(modelContext, term: term) ? modelContext : ""
            let fallback = bodySnippet(for: term, in: sourceText)
            let finalContext = safeModelContext.isEmpty ? fallback : safeModelContext
            result.append((term: term, context: finalContext.isEmpty ? term : finalContext))

            if result.count >= max { break }
        }
        return result
    }

    private func normalizeSource(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isGoodTerm(_ term: String) -> Bool {
        guard term.count >= 2, term.count <= 80 else { return false }
        guard term.rangeOfCharacter(from: .letters) != nil else { return false }
        return !noiseTerms.contains(term.lowercased())
    }

    private func bodySnippet(for term: String, in text: String) -> String {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 24 }

        for paragraph in paragraphs {
            let lower = paragraph.lowercased()
            if lower.contains(term.lowercased()), isAcceptableContext(paragraph, term: term) {
                return paragraph
            }
        }

        guard let range = text.range(of: term, options: [.caseInsensitive]) else { return "" }
        let lo = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let hi = text.index(range.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex
        let snippet = String(text[lo..<hi]).replacingOccurrences(of: "\n", with: " ")
        return isAcceptableContext(snippet, term: term) ? snippet : ""
    }

    private func isAcceptableContext(_ text: String, term: String) -> Bool {
        let cleaned = clean(text)
        guard cleaned.count >= 10 else { return false }
        let lower = cleaned.lowercased()
        if !lower.contains(term.lowercased()) { return false }
        if lower.contains("@") || lower.contains("http://") || lower.contains("https://") || lower.contains("www.") { return false }
        if lower.range(of: #"doi:\s*"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"\b(arxiv|isbn|issn|copyright|all rights reserved|et al\.?)\b"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"\b(university|institute|laboratory|inc\.?|corp\.?|corporation|ltd\.?|llc|gmbh)\b"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"^\s*\[\d+\]"#, options: .regularExpression) != nil { return false }
        return true
    }

    private var noiseTerms: Set<String> {
        ["introduction", "background", "overview", "conclusion", "future work", "result", "results", "discussion", "summary", "agenda", "thanks", "slide", "slides", "section", "appendix"]
    }

    private func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start <= end else {
            return nil
        }
        return String(text[start...end])
    }
}

private struct TermContextItem: Codable {
    let term: String
    let context: String
}
