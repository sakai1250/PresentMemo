import Foundation
import Combine
import SwiftUI

class StudyViewModel: ObservableObject {
    @Published var currentIndex = 0
    @Published var isFlipped    = false
    @Published var isComplete   = false
    @Published var isExplaining = false
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
        isExplaining = false
    }

    @MainActor
    func explainCurrentTermWithLlama() async {
        guard !isExplaining else { return }
        guard let card = current else { return }

        isExplaining = true
        defer { isExplaining = false }

        #if canImport(llama)
        guard let modelPath = resolveLlamaModelPath() else {
            explanationText = "llamaモデルが見つかりません。"
            return
        }

        let prompt = makeGroundedExplanationPrompt(for: card)
        let out = await LlamaExtractionService.shared.generate(
            modelPath: modelPath,
            prompt: prompt,
            maxTokens: 220
        )
        let cleaned = out.trimmingCharacters(in: .whitespacesAndNewlines)
        explanationText = cleaned.isEmpty ? "説明を生成できませんでした。" : cleaned
        #else
        explanationText = "このビルドではllamaが利用できません。"
        #endif
    }

    private func makeGroundedExplanationPrompt(for card: Flashcard) -> String {
        let contextBlocks = collectGroundingContexts(for: card.term)
        let contextText = contextBlocks.isEmpty
            ? "(本文抜粋が見つかりませんでした)"
            : contextBlocks.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")

        return """
あなたは学会発表準備のための説明アシスタントです。
次の専門用語を、必ず「資料本文抜粋」を根拠に日本語で説明してください。
出力ルール:
- 日本語のみ
- 3〜5文
- まず1文で定義、次に本文抜粋の内容に即して説明
- 最後に発表向けの一言アドバイスを1文
- 抜粋にない情報は推測で足さない

用語: \(card.term)
カード補足: \(card.example.isEmpty ? card.definition : card.example)

資料本文抜粋:
\(contextText)
"""
    }

    private func collectGroundingContexts(for term: String) -> [String] {
        let termLower = term.lowercased()
        let termWords = termLower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }

        let candidates = (
            deck.slideTexts +
            deck.slideNotes +
            deck.cards.map(\.example) +
            deck.cards.map(\.definition)
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.count >= 24 }

        let scored: [(text: String, score: Int)] = candidates.map { text in
            let lower = text.lowercased()
            var score = 0
            if lower.contains(termLower) { score += 8 }
            for word in termWords where lower.contains(word) { score += 1 }
            if text.count <= 260 { score += 1 }
            return (text: normalizeLine(text), score: score)
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }

        var unique: [String] = []
        var seen = Set<String>()
        for item in scored {
            let key = item.text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(String(item.text.prefix(240)))
            if unique.count >= 5 { break }
        }
        return unique
    }

    private func normalizeLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveLlamaModelPath() -> String? {
        let defaults = UserDefaults.standard
        let configured = defaults.string(forKey: "ai.llama.modelPath")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !configured.isEmpty {
            return configured
        }

        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL,
           let path = firstGGUF(in: resourceURL, fileManager: fm) {
            return path
        }

        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
           let path = firstGGUF(in: docs, fileManager: fm) {
            return path
        }
        return nil
    }

    private func firstGGUF(in root: URL, fileManager: FileManager) -> String? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "gguf" {
                return url.path
            }
        }
        return nil
    }
}
