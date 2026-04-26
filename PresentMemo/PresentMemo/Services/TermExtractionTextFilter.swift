import Foundation
import NaturalLanguage

enum TermExtractionDomain {
    case general
    case presentation
}

enum TermExtractionTextFilter {
    static func preprocessForImportantTerms(_ text: String, domain: TermExtractionDomain) -> String {
        let normalized = normalizeLineBreaks(text)
        let withoutReferences = removeReferencesSection(from: normalized)
        guard domain == .presentation else {
            return withoutReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let methodFocused = focusOnMethodSections(in: withoutReferences)
        if methodFocused.isEmpty {
            return withoutReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return methodFocused
    }

    static func isLikelyPersonOrPlace(_ text: String) -> Bool {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = term
        var hasPersonOrPlace = false
        tagger.enumerateTags(
            in: term.startIndex..<term.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, _ in
            if tag == .personalName || tag == .placeName {
                hasPersonOrPlace = true
                return false
            }
            return true
        }
        return hasPersonOrPlace
    }

    private static func normalizeLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func removeReferencesSection(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let cutIndex = lines.firstIndex(where: { isReferenceHeader($0) }) else {
            return text
        }
        return lines[..<cutIndex].joined(separator: "\n")
    }

    private static func focusOnMethodSections(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return "" }

        var selected = IndexSet()
        for (index, rawLine) in lines.enumerated() {
            if isMethodHeader(rawLine) {
                let lower = max(0, index - 2)
                let upper = min(lines.count - 1, index + 14)
                selected.insert(integersIn: lower...upper)
            }
        }

        if selected.isEmpty {
            let fallback = lines.filter { line in
                let lower = line.lowercased()
                return methodKeywords.contains(where: { lower.contains($0) }) ||
                    methodKeywordsJP.contains(where: { line.contains($0) })
            }
            return fallback.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let extracted = selected
            .compactMap { index -> String? in
                guard index < lines.count else { return nil }
                return lines[index]
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted
    }

    private static func isReferenceHeader(_ line: String) -> Bool {
        let normalized = normalizeSectionHeader(line)
        if normalized.isEmpty { return false }
        let refs = [
            "references", "reference", "bibliography", "works cited", "citations",
            "参考文献", "引用文献", "文献"
        ]
        return refs.contains(normalized)
    }

    private static func isMethodHeader(_ line: String) -> Bool {
        let normalized = normalizeSectionHeader(line)
        guard !normalized.isEmpty else { return false }
        if methodKeywords.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") }) {
            return true
        }
        return methodKeywordsJP.contains(where: { normalized.contains($0) })
    }

    private static func normalizeSectionHeader(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.count > 80 { return "" }
        value = value.replacingOccurrences(
            of: #"^\d+(\.\d+)*[\)\.\:\-]?\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: #"^[ivxlcdm]+[\)\.\:\-]?\s*"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[\:\-]+$"#, with: "", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let methodKeywords: [String] = [
        "proposed method",
        "method",
        "methodology",
        "approach",
        "proposed approach",
        "our approach",
        "our method",
        "model",
        "model architecture",
        "architecture",
        "algorithm",
        "framework",
        "implementation"
    ]

    private static let methodKeywordsJP: [String] = [
        "提案手法",
        "提案法",
        "手法",
        "方法",
        "提案モデル",
        "モデル",
        "アーキテクチャ",
        "アルゴリズム",
        "フレームワーク",
        "実装"
    ]
}
