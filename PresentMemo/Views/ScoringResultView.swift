import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ScoringResultView: View {
    let slideScores: [SlideScore]
    let averageScore: Int
    let deck: Deck
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    Divider().padding(.horizontal)
                    perSlideSection
                }
                .padding(.vertical)
            }
            .navigationTitle(L("scoring.result_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("button.close")) {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: averageScore >= 70 ? "trophy.fill" : "chart.bar.fill")
                .font(.system(size: 60))
                .foregroundStyle(colorForScore(averageScore))

            Text(L("scoring.complete"))
                .font(.title).bold()

            ProgressRing(progress: Double(averageScore) / 100.0, size: 100)

            Text(String(format: L("scoring.average"), averageScore))
                .font(.title3)

            Text(String(format: L("scoring.slides_scored"), slideScores.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Per-slide breakdown

    private var perSlideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("scoring.per_slide"))
                .font(.headline)
                .padding(.horizontal)

            ForEach(slideScores) { score in
                slideScoreRow(score)
                    .padding(.horizontal)
            }
        }
    }

    private func slideScoreRow(_ score: SlideScore) -> some View {
        HStack(spacing: 12) {
            // Slide thumbnail
            #if canImport(UIKit)
            if score.slideIndex < deck.slideImageData.count,
               let uiImage = UIImage(data: deck.slideImageData[score.slideIndex]) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 45)
                    .cornerRadius(6)
            } else {
                placeholderThumb(score.slideIndex)
            }
            #else
            placeholderThumb(score.slideIndex)
            #endif

            // Slide label
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: L("scoring.slide_number"), score.slideIndex + 1))
                    .font(.subheadline).bold()
                Text(L(score.tier.labelKey))
                    .font(.caption)
                    .foregroundStyle(colorForTier(score.tier))
            }

            Spacer()

            // Score badge
            HStack(spacing: 4) {
                Image(systemName: score.tier.iconName)
                    .foregroundStyle(colorForTier(score.tier))
                Text("\(score.normalizedScore)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(colorForTier(score.tier))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(colorForTier(score.tier).opacity(0.12))
            .cornerRadius(10)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func placeholderThumb(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 60, height: 45)
            .overlay(Text("\(index + 1)").font(.caption))
    }

    // MARK: - Helpers

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .blue
        case 40..<60:  return .orange
        default:       return .red
        }
    }

    private func colorForTier(_ tier: ScoreTier) -> Color {
        switch tier {
        case .excellent: return .green
        case .good:      return .blue
        case .fair:      return .orange
        case .poor:      return .red
        }
    }
}
