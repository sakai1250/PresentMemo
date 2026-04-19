import Foundation

struct Flashcard: Identifiable, Codable, Equatable {
    let id: UUID
    var term: String
    var definition: String
    var example: String
    var mastery: Int        // 0 = new … 5 = mastered
    var lastReviewed: Date?
    var reviewCount: Int

    init(id: UUID = UUID(),
         term: String,
         definition: String,
         example: String = "",
         mastery: Int = 0,
         lastReviewed: Date? = nil,
         reviewCount: Int = 0) {
        self.id = id
        self.term = term
        self.definition = definition
        self.example = example
        self.mastery = mastery
        self.lastReviewed = lastReviewed
        self.reviewCount = reviewCount
    }

    var masteryLevel: MasteryLevel {
        switch mastery {
        case 0:     return .new
        case 1...2: return .learning
        case 3...4: return .reviewing
        default:    return .mastered
        }
    }
}

enum MasteryLevel: String, CaseIterable {
    case new, learning, reviewing, mastered

    var label: String { NSLocalizedString("mastery.\(rawValue)", comment: "") }

    var colorName: String {
        switch self {
        case .new:       return "gray"
        case .learning:  return "red"
        case .reviewing: return "yellow"
        case .mastered:  return "green"
        }
    }
}
