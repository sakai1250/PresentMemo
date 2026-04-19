import Foundation
import Combine

class QuizViewModel: ObservableObject {
    @Published var questions:   [QuizQuestion] = []
    @Published var currentIndex = 0
    @Published var selected: Int? = nil
    @Published var revealed  = false
    @Published var score     = 0
    @Published var isComplete = false

    let deck: Deck
    weak var deckVM: DeckViewModel?

    init(deck: Deck, deckVM: DeckViewModel) {
        self.deck   = deck
        self.deckVM = deckVM
        questions   = QuizGenerator().generate(from: deck.cards)
    }

    var current: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex) / Double(questions.count)
    }

    func select(_ i: Int) {
        guard !revealed, let q = current else { return }
        selected = i
        revealed = true
        var card = q.card
        if i == q.correctIndex {
            score   += 1
            card.mastery = min(5, card.mastery + 1)
        } else {
            card.mastery = max(0, card.mastery - 1)
        }
        deckVM?.updateCard(card, inDeck: deck.id)
    }

    func next() {
        selected = nil; revealed = false
        if currentIndex < questions.count - 1 { currentIndex += 1 } else { isComplete = true }
    }

    func restart() {
        currentIndex = 0; selected = nil; revealed = false; score = 0; isComplete = false
        questions = QuizGenerator().generate(from: deck.cards)
    }
}
