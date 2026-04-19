import SwiftUI

struct CardStudyView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @StateObject private var vm: StudyViewModel
    @Environment(\.dismiss) private var dismiss

    init(deck: Deck) {
        _vm = StateObject(wrappedValue: StudyViewModel(deck: deck, deckVM: DeckViewModel()))
    }

    var body: some View {
        Group {
            if vm.isComplete {
                completeView
            } else if let card = vm.current {
                studyView(card: card)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(vm.deck.name)
        .onAppear { /* Inject real deckVM */ }
    }

    private func studyView(card: Flashcard) -> some View {
        VStack(spacing: 24) {
            // Progress
            ProgressView(value: vm.progress)
                .tint(.accentColor)
                .padding(.horizontal)
            Text("\(vm.currentIndex + 1) / \(vm.studyCards.count)")
                .font(.caption).foregroundStyle(.secondary)

            Spacer()

            // Flip card
            FlipCardView(front: card.term,
                         back: card.definition,
                         example: card.example,
                         isFlipped: $vm.isFlipped)
                .padding(.horizontal)

            VStack(spacing: 10) {
                Button {
                    Task { await vm.explainCurrentTermWithLlama() }
                } label: {
                    Label("説明", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isExplaining)
                .padding(.horizontal)

                if vm.isExplaining {
                    ProgressView("説明を生成中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !vm.explanationText.isEmpty {
                    ScrollView {
                        Text(vm.explanationText)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 150)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }

            Spacer()

            // Rating buttons
            if vm.isFlipped {
                HStack(spacing: 20) {
                    Button {
                        withAnimation { vm.rate(knew: false) }
                    } label: {
                        Label(L("study.dontknow"), systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.red.opacity(0.15)).cornerRadius(14)
                            .foregroundStyle(.red)
                    }
                    Button {
                        withAnimation { vm.rate(knew: true) }
                    } label: {
                        Label(L("study.know"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.green.opacity(0.15)).cornerRadius(14)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Color.clear.frame(height: 56).padding(.horizontal)
            }

            // Nav arrows
            HStack {
                Button { vm.back() } label: {
                    Image(systemName: "chevron.left.circle")
                        .font(.title2).foregroundStyle(vm.currentIndex > 0 ? .primary : .tertiary)
                }.disabled(vm.currentIndex == 0)
                Spacer()
                Button { withAnimation { vm.advance() } } label: {
                    Image(systemName: "chevron.right.circle")
                        .font(.title2).foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 32).padding(.bottom)
        }
    }

    private var completeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "star.fill").font(.system(size: 60)).foregroundStyle(.yellow)
            Text(L("study.complete")).font(.title).bold()
            ProgressRing(progress: Double(vm.deck.masteredCount) / Double(max(vm.deck.cards.count, 1)), size: 100)
            Button(L("study.restart")) { vm.restart() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

// Inject real deckVM via preference key workaround
extension CardStudyView {
    func injecting(_ dvm: DeckViewModel) -> some View {
        self.onAppear { vm.deckVM = dvm }
    }
}
