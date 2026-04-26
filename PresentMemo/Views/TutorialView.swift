import SwiftUI

enum CoachMarkStep: Int, CaseIterable, Hashable {
    case welcome
    case createDeck
    case done

    var title: String {
        switch self {
        case .welcome: return L("coach.welcome.title")
        case .createDeck: return L("coach.create.title")
        case .done: return L("coach.done.title")
        }
    }

    var message: String {
        switch self {
        case .welcome: return L("coach.welcome.body")
        case .createDeck: return L("coach.create.body")
        case .done: return L("coach.done.body")
        }
    }

    var hasTarget: Bool {
        switch self {
        case .createDeck: return true
        default: return false
        }
    }
}

final class CoachMarkManager: ObservableObject {
    @Published var currentStep: CoachMarkStep?
    @Published var targetFrames: [CoachMarkStep: CGRect] = [:]
    @Published var requestedTab: Int?

    var isActive: Bool { currentStep != nil }

    func startIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.completed") else { return }
        requestedTab = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { self.currentStep = .welcome }
        }
    }

    func restart() {
        requestedTab = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { self.currentStep = .welcome }
        }
    }

    func next() {
        guard let step = currentStep else { return }
        let all = CoachMarkStep.allCases
        guard let idx = all.firstIndex(of: step) else { return }
        if idx + 1 < all.count {
            withAnimation { currentStep = all[idx + 1] }
        } else {
            finish()
        }
    }

    func finish() {
        withAnimation { currentStep = nil }
        requestedTab = nil
        UserDefaults.standard.set(true, forKey: "tutorial.completed")
    }
}

// MARK: - Frame reporting

struct CoachMarkFrameKey: PreferenceKey {
    static var defaultValue: [CoachMarkStep: CGRect] = [:]
    static func reduce(value: inout [CoachMarkStep: CGRect], nextValue: () -> [CoachMarkStep: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func coachMarkTarget(_ step: CoachMarkStep) -> some View {
        self.background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: CoachMarkFrameKey.self,
                               value: [step: proxy.frame(in: .global)])
            }
        )
    }
}

// MARK: - Overlay

struct CoachMarkOverlay: View {
    @ObservedObject var manager: CoachMarkManager

    var body: some View {
        if let step = manager.currentStep {
            GeometryReader { proxy in
                let overlayOrigin = proxy.frame(in: .global).origin

                ZStack {
                    dimBackground(step: step, proxy: proxy, overlayOrigin: overlayOrigin)
                    tooltipCard(step: step, proxy: proxy, overlayOrigin: overlayOrigin)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func dimBackground(step: CoachMarkStep, proxy: GeometryProxy, overlayOrigin: CGPoint) -> some View {
        Color.black.opacity(0.6)
            .overlay {
                if step.hasTarget, let frame = manager.targetFrames[step] {
                    let localRect = frame.offsetBy(dx: -overlayOrigin.x, dy: -overlayOrigin.y)
                    RoundedRectangle(cornerRadius: 14)
                        .frame(width: localRect.width + 16, height: localRect.height + 16)
                        .position(x: localRect.midX, y: localRect.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
    }

    private func tooltipCard(step: CoachMarkStep, proxy: GeometryProxy, overlayOrigin: CGPoint) -> some View {
        let card = VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(.headline)

            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button(L("coach.skip")) {
                    manager.finish()
                }
                .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    manager.next()
                } label: {
                    Text(step == CoachMarkStep.allCases.last
                         ? L("coach.start")
                         : L("tutorial.next"))
                        .bold()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 24)

        let position = tooltipPosition(step: step, proxy: proxy, overlayOrigin: overlayOrigin)
        return card.position(position)
    }

    private func tooltipPosition(step: CoachMarkStep, proxy: GeometryProxy, overlayOrigin: CGPoint) -> CGPoint {
        let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

        guard step.hasTarget, let frame = manager.targetFrames[step] else {
            return center
        }

        let localRect = frame.offsetBy(dx: -overlayOrigin.x, dy: -overlayOrigin.y)
        let cardHeight: CGFloat = 160
        let padding: CGFloat = 24

        if localRect.midY < proxy.size.height / 2 {
            return CGPoint(x: center.x, y: localRect.maxY + padding + cardHeight / 2)
        } else {
            return CGPoint(x: center.x, y: localRect.minY - padding - cardHeight / 2)
        }
    }
}
