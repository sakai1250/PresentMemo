import Foundation

enum CSVService {

    // MARK: - Generic CSV parsing

    /// Parse CSV string into rows of fields, handling quoted fields.
    static func parseRows(from csvString: String) -> [[String]] {
        var rows: [[String]] = []
        for line in csvString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            rows.append(parseLine(trimmed))
        }
        return rows
    }

    /// Parse a single CSV line handling quoted fields.
    private static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    /// Check if a row looks like a header (common header keywords).
    private static func isHeaderRow(_ fields: [String]) -> Bool {
        let headerWords = Set(["english", "japanese", "term", "definition", "example",
                               "英語", "日本語", "用語", "定義", "例文"])
        let lowered = fields.map { $0.lowercased() }
        return lowered.contains(where: { headerWords.contains($0) })
    }

    // MARK: - Glossary (English, Japanese)

    static func parseGlossary(from csvString: String) -> [GlossaryTerm] {
        let rows = parseRows(from: csvString)
        var terms: [GlossaryTerm] = []
        for row in rows {
            guard row.count >= 2 else { continue }
            if isHeaderRow(row) { continue }
            let english = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let japanese = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, !japanese.isEmpty else { continue }
            terms.append(GlossaryTerm(english: english, japanese: japanese))
        }
        return terms
    }

    static func exportGlossary(_ terms: [GlossaryTerm]) -> String {
        var lines = ["English,Japanese"]
        for term in terms {
            lines.append("\(escapeCSV(term.english)),\(escapeCSV(term.japanese))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Flashcards (term, definition, example)

    static func parseFlashcards(from csvString: String) -> [Flashcard] {
        let rows = parseRows(from: csvString)
        var cards: [Flashcard] = []
        for row in rows {
            guard row.count >= 2 else { continue }
            if isHeaderRow(row) { continue }
            let term = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let example = row.count >= 3 ? row[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard !term.isEmpty, !definition.isEmpty else { continue }
            cards.append(Flashcard(term: term, definition: definition, example: example))
        }
        return cards
    }

    static func exportFlashcards(_ cards: [Flashcard]) -> String {
        var lines = ["term,definition,example"]
        for card in cards {
            lines.append("\(escapeCSV(card.term)),\(escapeCSV(card.definition)),\(escapeCSV(card.example))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
