import Foundation

struct Deck: Identifiable, Codable {
    let id: UUID
    var name: String
    var mode: AppMode
    var cards: [Flashcard]
    var slideTexts: [String]    // extracted slide body text (PowerPoint/PDF mode)
    var slideNotes: [String]    // rehearsal notes
    var slideImageData: [Data]  // rendered slide images (PDF import mode)
    var createdAt: Date
    var updatedAt: Date
    var notificationIntervalHours: Int  // 0 = disabled

    init(id: UUID = UUID(),
         name: String,
         mode: AppMode = .default,
         cards: [Flashcard] = [],
         slideTexts: [String] = [],
         slideNotes: [String] = [],
         slideImageData: [Data] = [],
         notificationIntervalHours: Int = 24) {
        self.id = id
        self.name = name
        self.mode = mode
        self.cards = cards
        self.slideTexts = slideTexts
        self.slideNotes = slideNotes
        self.slideImageData = slideImageData
        self.createdAt = Date()
        self.updatedAt = Date()
        self.notificationIntervalHours = notificationIntervalHours
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case cards
        case slideTexts
        case slideNotes
        case slideImageData
        case createdAt
        case updatedAt
        case notificationIntervalHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(AppMode.self, forKey: .mode)
        cards = try c.decodeIfPresent([Flashcard].self, forKey: .cards) ?? []
        slideTexts = try c.decodeIfPresent([String].self, forKey: .slideTexts) ?? []
        slideNotes = try c.decodeIfPresent([String].self, forKey: .slideNotes) ?? []
        slideImageData = try c.decodeIfPresent([Data].self, forKey: .slideImageData) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        notificationIntervalHours = try c.decodeIfPresent(Int.self, forKey: .notificationIntervalHours) ?? 24
    }

    var masteredCount: Int { cards.filter { $0.mastery == 5 }.count }

    var progressRatio: Double {
        guard !cards.isEmpty else { return 0 }
        let total = cards.reduce(0) { $0 + $1.mastery }
        return Double(total) / Double(cards.count * 5)
    }
}
