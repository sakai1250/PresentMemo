import SwiftUI
import AVFoundation

struct ListeningModeView: View {
    @StateObject private var vm: ListeningModeViewModel
    @AppStorage("listening.playbackMode") private var playbackModeRawValue: Int = ListeningPlaybackMode.termThenDefinition.rawValue
    @AppStorage("listening.loopEnabled") private var loopEnabled: Bool = false
    @AppStorage("listening.intervalSeconds") private var intervalSeconds: Double = 1.0

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
                VStack(alignment: .leading, spacing: 12) {
                    Picker(L("listening.mode"), selection: Binding(
                        get: { ListeningPlaybackMode(rawValue: playbackModeRawValue) ?? .termThenDefinition },
                        set: { value in
                            playbackModeRawValue = value.rawValue
                            vm.playbackMode = value
                        }
                    )) {
                        ForEach(ListeningPlaybackMode.allCases, id: \.self) { mode in
                            Text(mode.labelKey).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(L("listening.loop"), isOn: Binding(
                        get: { loopEnabled },
                        set: { value in
                            loopEnabled = value
                            vm.loopEnabled = value
                        }
                    ))

                    HStack {
                        Text(L("listening.interval"))
                        Spacer()
                        Text(String(format: L("listening.interval_value"), intervalSeconds))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { intervalSeconds },
                        set: { value in
                            intervalSeconds = value
                            vm.intervalSeconds = value
                        }
                    ), in: 0...5, step: 0.5)
                }
                .padding(.horizontal)

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
        .onAppear {
            vm.playbackMode = ListeningPlaybackMode(rawValue: playbackModeRawValue) ?? .termThenDefinition
            vm.loopEnabled = loopEnabled
            vm.intervalSeconds = intervalSeconds
        }
        .onDisappear { vm.stop() }
    }
}

enum ListeningPlaybackMode: Int, CaseIterable {
    case termThenDefinition
    case termOnly

    var labelKey: String {
        switch self {
        case .termThenDefinition: return L("listening.mode.term_to_definition")
        case .termOnly: return L("listening.mode.term_only")
        }
    }
}

final class ListeningModeViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false

    var playbackMode: ListeningPlaybackMode = .termThenDefinition
    var loopEnabled: Bool = false
    var intervalSeconds: Double = 1.0

    let cards: [Flashcard]
    private let synthesizer = AVSpeechSynthesizer()
    private var remainingUtterancesInCurrentCard = 0
    private var scheduledAdvance: DispatchWorkItem?

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
        scheduledAdvance?.cancel()
        scheduledAdvance = nil
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
    }

    func stop() {
        scheduledAdvance?.cancel()
        scheduledAdvance = nil
        synthesizer.stopSpeaking(at: .immediate)
        remainingUtterancesInCurrentCard = 0
        isPlaying = false
    }

    func next() {
        guard !cards.isEmpty else { return }
        scheduledAdvance?.cancel()
        scheduledAdvance = nil
        currentIndex = min(currentIndex + 1, cards.count - 1)
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            speakCurrentCard()
        }
    }

    func previous() {
        guard !cards.isEmpty else { return }
        scheduledAdvance?.cancel()
        scheduledAdvance = nil
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
        scheduleAdvanceToNextCard()
    }

    private func speakCurrentCard() {
        guard !cards.isEmpty else { return }

        let card = currentCard
        let segments = playbackSegments(for: card)

        guard !segments.isEmpty else { return }

        scheduledAdvance?.cancel()
        scheduledAdvance = nil
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

    private func playbackSegments(for card: Flashcard) -> [String] {
        switch playbackMode {
        case .termThenDefinition:
            return [card.term, card.definition]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .termOnly:
            let term = card.term.trimmingCharacters(in: .whitespacesAndNewlines)
            return term.isEmpty ? [] : [term]
        }
    }

    private func scheduleAdvanceToNextCard() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying else { return }
            if self.currentIndex < self.cards.count - 1 {
                self.currentIndex += 1
                self.speakCurrentCard()
            } else if self.loopEnabled {
                self.currentIndex = 0
                self.speakCurrentCard()
            } else {
                self.isPlaying = false
            }
        }
        scheduledAdvance = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, intervalSeconds), execute: work)
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
