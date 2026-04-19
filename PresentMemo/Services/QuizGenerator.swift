import Foundation

class QuizGenerator {
    func generate(from cards: [Flashcard], count: Int = 10) -> [QuizQuestion] {
        guard cards.count >= 2 else { return [] }
        return cards.shuffled().prefix(min(count, cards.count)).map {
            makeQuestion(for: $0, pool: cards)
        }
    }

    private func makeQuestion(for card: Flashcard, pool: [Flashcard]) -> QuizQuestion {
        let correct = card.definition
        let candidates = pool
            .filter { $0.id != card.id }
            .filter { !$0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { other in
                (text: other.definition, score: lexicalSimilarity(correct, other.definition))
            }
            .sorted { $0.score > $1.score }

        var distractors = candidates.prefix(3).map(\.text)

        // If deck has too few cards, create deck-aware distractors from terms.
        if distractors.count < 3 {
            let termBased = pool
                .filter { $0.id != card.id }
                .map { "\($0.term): \($0.definition)" }
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
