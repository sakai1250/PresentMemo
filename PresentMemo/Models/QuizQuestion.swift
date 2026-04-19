import Foundation

struct QuizQuestion: Identifiable {
    let id = UUID()
    let card: Flashcard
    let choices: [String]
    let correctIndex: Int
}
