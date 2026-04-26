import SwiftUI
import AVFoundation

struct ListeningModeView: View {
    @StateObject private var vm: ListeningModeViewModel

    init(deck: Deck) {
        _vm = StateObject(wrappedValue: ListeningModeViewModel(deck: deck))
    }

    var body: some View {
        VStack(spacing: 20) {
            if vm.cards.isEmpty {
                Spacer()
                Text(L("deck.empty_cards"))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("\(vm.currentIndex + 1) / \(vm.cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text(vm.currentCard.term)
                        .font(.title3.bold())
                    Text(vm.currentCard.definition)
                        .font(.body)
                    if !vm.currentCard.example.isEmpty {
                        Text(vm.currentCard.example)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.primary.opacity(0.04))
                .cornerRadius(12)
                .padding(.horizontal)

                HStack(spacing: 24) {
                    Button { vm.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }

                    Button {
                        vm.isPlaying ? vm.pause() : vm.play()
                    } label: {
                        Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }

                    Button { vm.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                }
            }
            Spacer()
        }
        .padding(.top)
        .navigationTitle(L("listening.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.stop() }
    }
}

final class ListeningModeViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false

    let cards: [Flashcard]
    private let synthesizer = AVSpeechSynthesizer()
    private var remainingUtterancesInCurrentCard = 0

    var currentCard: Flashcard {
        cards[currentIndex]
    }

    init(deck: Deck) {
        self.cards = deck.cards.sorted {
            if $0.mastery != $1.mastery { return $0.mastery < $1.mastery }
            if $0.reviewCount != $1.reviewCount { return $0.reviewCount < $1.reviewCount }
            return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }
        super.init()
        synthesizer.delegate = self
    }

    func play() {
        guard !cards.isEmpty else { return }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
            return
        }
        isPlaying = true
        speakCurrentCard()
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        remainingUtterancesInCurrentCard = 0
        isPlaying = false
    }

    func next() {
        guard !cards.isEmpty else { return }
        currentIndex = min(currentIndex + 1, cards.count - 1)
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            speakCurrentCard()
        }
    }

    func previous() {
        guard !cards.isEmpty else { return }
        currentIndex = max(currentIndex - 1, 0)
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            speakCurrentCard()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isPlaying else { return }

        if remainingUtterancesInCurrentCard > 0 {
            remainingUtterancesInCurrentCard -= 1
        }

        guard remainingUtterancesInCurrentCard == 0 else { return }

        if currentIndex < cards.count - 1 {
            currentIndex += 1
            speakCurrentCard()
        } else {
            isPlaying = false
        }
    }

    private func speakCurrentCard() {
        guard !cards.isEmpty else { return }

        let card = currentCard
        let segments = [card.term, card.definition, card.example]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !segments.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        remainingUtterancesInCurrentCard = segments.count

        for text in segments {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: preferredLanguage(for: text))
            utterance.rate = 0.46
            utterance.pitchMultiplier = 1.0
            synthesizer.speak(utterance)
        }
    }

    private func preferredLanguage(for text: String) -> String {
        containsJapanese(text) ? "ja-JP" : "en-US"
    }

    private func containsJapanese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF:
                return true
            default:
                continue
            }
        }
        return false
    }
}
