import SwiftUI

struct QuizView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @StateObject private var vm: QuizViewModel

    init(deck: Deck) {
        _vm = StateObject(wrappedValue: QuizViewModel(deck: deck, deckVM: DeckViewModel()))
    }

    var body: some View {
        Group {
            if vm.isComplete { resultView }
            else if let q = vm.current { questionView(q) }
            else { ProgressView() }
        }
        .navigationTitle(L("quiz.title"))
    }

    private func questionView(_ q: QuizQuestion) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: vm.progress).padding(.horizontal)
            Text(String(format: L("quiz.question"), vm.currentIndex + 1, vm.questions.count))
                .font(.caption).foregroundStyle(.secondary)

            // Term
            Text(q.card.term)
                .font(.title2).bold()
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)

            // Choices
            VStack(spacing: 10) {
                ForEach(0..<q.choices.count, id: \.self) { i in
                    ChoiceButton(
                        text: q.choices[i],
                        state: choiceState(i, q),
                        action: { vm.select(i) }
                    )
                    .disabled(vm.revealed)
                }
            }
            .padding(.horizontal)

            if vm.revealed {
                VStack(spacing: 10) {
                    if let sel = vm.selected {
                        Label(sel == q.correctIndex ? L("quiz.correct") : L("quiz.wrong"),
                              systemImage: sel == q.correctIndex ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(sel == q.correctIndex ? .green : .red)
                            .font(.headline)
                    }
                    Button(L("quiz.next")) { withAnimation { vm.next() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
        }
    }

    private func choiceState(_ i: Int, _ q: QuizQuestion) -> ChoiceButton.State {
        guard vm.revealed else { return .normal }
        if i == q.correctIndex { return .correct }
        if i == vm.selected    { return .wrong }
        return .normal
    }

    private var resultView: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill").font(.system(size: 60)).foregroundStyle(.yellow)
            Text(L("quiz.complete")).font(.title).bold()
            Text(String(format: L("quiz.score"), vm.score, vm.questions.count))
                .font(.title3)
            Button(L("quiz.restart")) { vm.restart() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

struct ChoiceButton: View {
    enum State { case normal, correct, wrong }
    let text: String; let state: State; let action: () -> Void

    var bg: Color {
        switch state {
        case .normal:  return Color.secondary.opacity(0.12)
        case .correct: return .green.opacity(0.2)
        case .wrong:   return .red.opacity(0.2)
        }
    }
    var border: Color {
        switch state {
        case .normal:  return .clear
        case .correct: return .green
        case .wrong:   return .red
        }
    }
    var body: some View {
        Button(action: action) {
            Text(text).font(.subheadline).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(bg)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 2))
        }
        .foregroundStyle(.primary)
    }
}
