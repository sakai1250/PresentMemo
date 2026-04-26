import Foundation
import Combine
import SwiftUI

class StudyViewModel: ObservableObject {
    @Published var currentIndex = 0
    @Published var isFlipped    = false
    @Published var isComplete   = false
    @Published var explanationText = ""

    private(set) var studyCards: [Flashcard]
    let deck: Deck
    weak var deckVM: DeckViewModel?

    init(deck: Deck, deckVM: DeckViewModel) {
        self.deck = deck
        self.deckVM = deckVM
        // Study least-mastered first
        studyCards = deck.cards.sorted { $0.mastery < $1.mastery }
    }

    var current: Flashcard? {
        guard currentIndex < studyCards.count else { return nil }
        return studyCards[currentIndex]
    }

    var progress: Double {
        guard !studyCards.isEmpty else { return 0 }
        return Double(currentIndex) / Double(studyCards.count)
    }

    func flip() { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isFlipped.toggle() } }

    func rate(knew: Bool) {
        guard var card = current else { return }
        card.mastery       = knew ? min(5, card.mastery + 1) : max(0, card.mastery - 1)
        card.lastReviewed  = Date()
        card.reviewCount  += 1
        deckVM?.updateCard(card, inDeck: deck.id)
        if let i = studyCards.firstIndex(where: { $0.id == card.id }) { studyCards[i] = card }
        explanationText = ""
        advance()
    }

    func advance() {
        isFlipped = false
        explanationText = ""
        if currentIndex < studyCards.count - 1 { currentIndex += 1 } else { isComplete = true }
    }

    func back() {
        if currentIndex > 0 {
            isFlipped = false
            explanationText = ""
            currentIndex -= 1
        }
    }

    func restart() {
        currentIndex = 0; isFlipped = false; isComplete = false
        studyCards = deck.cards.sorted { $0.mastery < $1.mastery }
        explanationText = ""
    }

    @MainActor
    func explainCurrentCardFromExample() {
        guard let card = current else { return }

        let sentence = card.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = card.example.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if !sentence.isEmpty {
            lines.append("例文: \(sentence)")
        }
        if !note.isEmpty, note != sentence {
            lines.append(note)
        }
        explanationText = lines.isEmpty ? "例文がありません。" : lines.joined(separator: "\n")
    }
}
