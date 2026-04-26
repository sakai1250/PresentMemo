import Foundation

class QuizGenerator {
    func generate(from cards: [Flashcard], count: Int = 10) -> [QuizQuestion] {
        guard cards.count >= 2 else { return [] }
        return cards.shuffled().prefix(min(count, cards.count)).map {
            makeQuestion(for: $0, pool: cards)
        }
    }

    private func makeQuestion(for card: Flashcard, pool: [Flashcard]) -> QuizQuestion {
        let correct = quizAnswerText(for: card)
        let candidates = pool
            .filter { $0.id != card.id }
            .map { other in
                let answer = quizAnswerText(for: other)
                return (text: answer, score: lexicalSimilarity(correct, answer))
            }
            .filter { !$0.text.isEmpty }
            .sorted { $0.score > $1.score }

        var distractors = candidates.prefix(3).map(\.text)

        // If deck has too few cards, create deck-aware distractors from terms.
        if distractors.count < 3 {
            let termBased = pool
                .filter { $0.id != card.id }
                .map { "\($0.term): \(quizAnswerText(for: $0))" }
                .filter { !distractors.contains($0) && $0 != correct }
            for candidate in termBased where distractors.count < 3 {
                distractors.append(candidate)
            }
        }

        while distractors.count < 3 {
            let fallback = "Concept related to \(card.term), but not its definition."
            if !distractors.contains(fallback) {
                distractors.append(fallback)
            } else {
                distractors.append("Alternative explanation for \(card.term)")
            }
        }

        var choices = Array(distractors)
        let correctIdx = Int.random(in: 0...3)
        choices.insert(correct, at: correctIdx)
        return QuizQuestion(card: card, choices: choices, correctIndex: correctIdx)
    }

    private func quizAnswerText(for card: Flashcard) -> String {
        let example = card.example.trimmingCharacters(in: .whitespacesAndNewlines)
        if example.hasPrefix("日本語訳:") {
            let translated = example.replacingOccurrences(of: "日本語訳:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !translated.isEmpty {
                return translated
            }
        }

        let definition = card.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        if definition.count > 120 {
            return String(definition.prefix(120))
        }
        return definition
    }

    private func lexicalSimilarity(_ a: String, _ b: String) -> Int {
        let tokensA = Set(tokenize(a))
        let tokensB = Set(tokenize(b))
        return tokensA.intersection(tokensB).count
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }
}
