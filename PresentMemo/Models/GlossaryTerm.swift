import Foundation

struct GlossaryTerm: Identifiable, Codable, Equatable {
    let id: UUID
    var english: String
    var japanese: String

    init(id: UUID = UUID(), english: String, japanese: String) {
        self.id = id
        self.english = english
        self.japanese = japanese
    }
}
