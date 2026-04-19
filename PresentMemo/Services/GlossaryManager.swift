import Foundation

class GlossaryManager: ObservableObject {
    static let shared = GlossaryManager()

    @Published var terms: [GlossaryTerm] = []

    private let key = "pm_glossary_v1"

    private init() {
        terms = load()
    }

    // MARK: - CRUD

    func add(_ term: GlossaryTerm) {
        terms.append(term)
        save()
    }

    func update(_ term: GlossaryTerm) {
        guard let i = terms.firstIndex(where: { $0.id == term.id }) else { return }
        terms[i] = term
        save()
    }

    func delete(at offsets: IndexSet) {
        terms.remove(atOffsets: offsets)
        save()
    }

    func deleteById(_ id: UUID) {
        terms.removeAll { $0.id == id }
        save()
    }

    /// Import terms from CSV, merging with existing (skip duplicates by English key).
    func importTerms(_ newTerms: [GlossaryTerm]) -> Int {
        let existingKeys = Set(terms.map { $0.english.lowercased() })
        var added = 0
        for term in newTerms {
            if !existingKeys.contains(term.english.lowercased()) {
                terms.append(term)
                added += 1
            }
        }
        if added > 0 { save() }
        return added
    }

    /// Returns lowercased English → Japanese dictionary for TranslationService.
    func dictionary() -> [String: String] {
        var dict: [String: String] = [:]
        for term in terms {
            dict[term.english.lowercased()] = term.japanese
        }
        return dict
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(terms) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() -> [GlossaryTerm] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let terms = try? JSONDecoder().decode([GlossaryTerm].self, from: data)
        else { return [] }
        return terms
    }
}
