import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum RehearsalPhase { case slide, keywords, fullText }

class RehearsalViewModel: ObservableObject {
    @Published var slideIndex: Int = 0
    @Published var phase: RehearsalPhase = .slide
    @Published var running  = false
    @Published var complete = false

    // Scoring mode
    @Published var scoringMode = false
    @Published var scoringInProgress = false
    @Published var scoringProgress: Float = 0.0
    @Published var slideScores: [SlideScore] = []
    @Published var scoringError: String? = nil

    var slideDelay:   Double = 5.0
    var keywordDelay: Double = 5.0

    let deck: Deck
    private var timer: Timer?
    private var scoringTask: Task<Void, Never>?

    init(deck: Deck) { self.deck = deck }

    var totalSlides: Int {
        Swift.max(deck.slideTexts.count, Swift.max(deck.slideNotes.count, deck.slideImageData.count))
    }

    var currentNotes: String {
        if slideIndex < deck.slideNotes.count, !deck.slideNotes[slideIndex].isEmpty {
            return deck.slideNotes[slideIndex]
        }
        if slideIndex < deck.slideTexts.count {
            return deck.slideTexts[slideIndex]
        }
        return ""
    }

    var currentBodyText: String {
        guard slideIndex < deck.slideTexts.count else { return "" }
        return deck.slideTexts[slideIndex]
    }

    var currentSlideImageData: Data? {
        guard slideIndex < deck.slideImageData.count else { return nil }
        let data = deck.slideImageData[slideIndex]
        return data.isEmpty ? nil : data
    }

    var keywords: [String] {
        currentNotes.components(separatedBy: .whitespaces).filter {
            let w = $0.trimmingCharacters(in: .punctuationCharacters)
            return w.count > 3 && (w.first?.isUppercase == true || w.contains("-"))
        }.map { $0.trimmingCharacters(in: .punctuationCharacters) }
    }

    func start() { running = true; phase = .slide; scheduleTimer() }
    func pause() { running = false; timer?.invalidate() }
    func resume() { running = true; scheduleTimer() }

    private func scheduleTimer() {
        timer?.invalidate()
        let delay = phase == .slide ? slideDelay : (phase == .keywords ? keywordDelay : 0)
        guard delay > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.advancePhase()
        }
    }

    private func advancePhase() {
        switch phase {
        case .slide:    phase = .keywords; scheduleTimer()
        case .keywords: phase = .fullText
        case .fullText: break
        }
    }

    func nextSlide() {
        if slideIndex < totalSlides - 1 {
            slideIndex += 1; phase = .slide
            if running { scheduleTimer() }
        } else { complete = true; running = false }
    }

    func prevSlide() {
        if slideIndex > 0 {
            slideIndex -= 1; phase = .slide
            if running { scheduleTimer() }
        }
    }

    func restart() { slideIndex = 0; phase = .slide; complete = false; timer?.invalidate() }

    // MARK: - Scoring

    var averageScore: Int {
        guard !slideScores.isEmpty else { return 0 }
        return slideScores.reduce(0) { $0 + $1.normalizedScore } / slideScores.count
    }

    var scorableSlideCount: Int {
        (0..<totalSlides).filter { index in
            let hasImage = index < deck.slideImageData.count && !deck.slideImageData[index].isEmpty
            let hasText = textForSlide(index) != nil
            return hasImage && hasText
        }.count
    }

    func startScoring() {
        guard !scoringInProgress else { return }
        scoringInProgress = true
        scoringProgress = 0.0
        slideScores = []
        scoringError = nil
        pause()

        scoringTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let scorableIndices = (0..<self.totalSlides).filter { index in
                let hasImage = index < self.deck.slideImageData.count && !self.deck.slideImageData[index].isEmpty
                let hasText = self.textForSlide(index) != nil
                return hasImage && hasText
            }

            guard !scorableIndices.isEmpty else {
                self.scoringError = L("scoring.no_scorable_slides")
                self.scoringInProgress = false
                return
            }

            var results: [SlideScore] = []

            for (processed, index) in scorableIndices.enumerated() {
                guard !Task.isCancelled else { break }

                let imageData = self.deck.slideImageData[index]
                #if canImport(UIKit)
                guard let uiImage = UIImage(data: imageData),
                      let text = self.textForSlide(index) else { continue }

                do {
                    let raw = try await CLIPScoringService.shared.computeRelevanceScore(
                        slideImage: uiImage,
                        speechText: text
                    )
                    let normalized = SlideScore.normalize(raw)
                    results.append(SlideScore(
                        slideIndex: index,
                        rawScore: raw,
                        normalizedScore: normalized,
                        hasImage: true,
                        hasText: true
                    ))
                } catch {
                    results.append(SlideScore(
                        slideIndex: index,
                        rawScore: 0,
                        normalizedScore: 0,
                        hasImage: true,
                        hasText: true
                    ))
                }
                #endif

                self.scoringProgress = Float(processed + 1) / Float(scorableIndices.count)
            }

            self.slideScores = results
            self.scoringInProgress = false
            if !results.isEmpty {
                self.scoringMode = true
            }
        }
    }

    func cancelScoring() {
        scoringTask?.cancel()
        scoringInProgress = false
    }

    func dismissScoring() {
        scoringMode = false
        slideScores = []
        scoringProgress = 0.0
        scoringError = nil
    }

    private func textForSlide(_ index: Int) -> String? {
        if index < deck.slideNotes.count, !deck.slideNotes[index].isEmpty {
            return deck.slideNotes[index]
        }
        if index < deck.slideTexts.count, !deck.slideTexts[index].isEmpty {
            return deck.slideTexts[index]
        }
        return nil
    }

    deinit {
        timer?.invalidate()
        scoringTask?.cancel()
    }
}
