import Foundation

class PersistenceManager {
    static let shared = PersistenceManager()
    private init() {}
    private let key = "pm_decks_v1"

    func save(_ decks: [Deck]) {
        if let data = try? JSONEncoder().encode(decks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [Deck] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decks = try? JSONDecoder().decode([Deck].self, from: data)
        else { return [] }
        return decks
    }

    func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
