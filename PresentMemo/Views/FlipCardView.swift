import SwiftUI

struct FlipCardView: View {
    let front: String
    let back: String
    let example: String
    @Binding var isFlipped: Bool

    private var japaneseTranslation: String? {
        let trimmed = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("日本語訳:") else { return nil }
        let value = trimmed.replacingOccurrences(of: "日本語訳:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        ZStack {
            // Back
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.03))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .overlay(
                    VStack(spacing: 12) {
                        Text(front).font(.title3).bold().foregroundStyle(.secondary)
                        Divider()
                        Text(back).font(.body).multilineTextAlignment(.center)

                        if let translated = japaneseTranslation {
                            Text(translated)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        } else if !example.isEmpty {
                            Text(example).font(.caption).italic()
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(24)
                )
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (0, 1, 0))
                .opacity(isFlipped ? 1 : 0)

            // Front
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.accentColor)
                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 4)
                .overlay(
                    VStack(spacing: 8) {
                        Text(front).font(.largeTitle).bold().foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(L("study.tap_flip")).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(24)
                )
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (0, 1, 0))
                .opacity(isFlipped ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isFlipped.toggle()
            }
        }
    }
}
