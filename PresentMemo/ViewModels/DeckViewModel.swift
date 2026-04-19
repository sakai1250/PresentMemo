import Foundation
import Combine

class DeckViewModel: ObservableObject {
    @Published var decks: [Deck] = []

    private let persist = PersistenceManager.shared
    private let notif   = NotificationManager.shared

    init() {
        decks = persist.load()
        if decks.isEmpty { createDefaultDeck() }
    }

    private func createDefaultDeck() {
        let d = Deck(name: NSLocalizedString("deck.default.name", comment: ""),
                     mode: .default,
                     cards: DefaultVocabulary.cards,
                     notificationIntervalHours: 24)
        add(d)
    }

    func add(_ deck: Deck) {
        decks.append(deck)
        save()
        notif.schedule(for: deck)
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { notif.cancel(for: decks[$0].id) }
        decks.remove(atOffsets: offsets)
        save()
    }

    func update(_ deck: Deck) {
        if let i = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[i] = deck
            save()
            notif.schedule(for: deck)
        }
    }

    func updateCard(_ card: Flashcard, inDeck deckId: UUID) {
        guard let di = decks.firstIndex(where: { $0.id == deckId }),
              let ci = decks[di].cards.firstIndex(where: { $0.id == card.id })
        else { return }
        decks[di].cards[ci] = card
        decks[di].updatedAt  = Date()
        save()
    }

    func addCards(_ cards: [Flashcard], toDeck deckId: UUID) {
        guard let i = decks.firstIndex(where: { $0.id == deckId }) else { return }
        decks[i].cards.append(contentsOf: cards)
        decks[i].updatedAt = Date()
        save()
    }

    func addCard(_ card: Flashcard, toDeck deckId: UUID) {
        guard let i = decks.firstIndex(where: { $0.id == deckId }) else { return }
        decks[i].cards.append(card)
        decks[i].updatedAt = Date()
        save()
    }

    func deleteCard(_ cardId: UUID, fromDeck deckId: UUID) {
        guard let di = decks.firstIndex(where: { $0.id == deckId }),
              let ci = decks[di].cards.firstIndex(where: { $0.id == cardId })
        else { return }
        decks[di].cards.remove(at: ci)
        decks[di].updatedAt = Date()
        save()
    }

    func clearAll() {
        notif.cancelAll()
        decks = []
        persist.clear()
    }

    private func save() { persist.save(decks) }
}
