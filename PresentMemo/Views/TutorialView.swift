import SwiftUI

// MARK: - Steps

enum CoachMarkStep: Int, CaseIterable, Hashable {
    case tapCreate
    case selectManual
    case tapSave
    case tapDeck
    case addCard
    case fillCard
    case done

    var title: String {
        switch self {
        case .tapCreate: return L("coach.tap_create.title")
        case .selectManual: return L("coach.select_manual.title")
        case .tapSave: return L("coach.tap_save.title")
        case .tapDeck: return L("coach.tap_deck.title")
        case .addCard: return L("coach.add_card.title")
        case .fillCard: return L("coach.fill_card.title")
        case .done: return L("coach.done.title")
        }
    }

    var message: String {
        switch self {
        case .tapCreate: return L("coach.tap_create.body")
        case .selectManual: return L("coach.select_manual.body")
        case .tapSave: return L("coach.tap_save.body")
        case .tapDeck: return L("coach.tap_deck.body")
        case .addCard: return L("coach.add_card.body")
        case .fillCard: return L("coach.fill_card.body")
        case .done: return L("coach.done.body")
        }
    }

    var isInteractive: Bool {
        switch self {
        case .done: return false
        default: return true
        }
    }
}

// MARK: - Manager

final class CoachMarkManager: ObservableObject {
    @Published var currentStep: CoachMarkStep?
    @Published var requestedTab: Int?

    var isActive: Bool { currentStep != nil }

    func startIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.completed") else { return }
        requestedTab = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { self.currentStep = .tapCreate }
        }
    }

    func restart() {
        requestedTab = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { self.currentStep = .tapCreate }
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

    func advance(from step: CoachMarkStep) {
        guard currentStep == step else { return }
        next()
    }

    func finish() {
        withAnimation { currentStep = nil }
        requestedTab = nil
        UserDefaults.standard.set(true, forKey: "tutorial.completed")
    }
}

// MARK: - Anchor Preference

struct CoachTargetKey: PreferenceKey {
    static var defaultValue: [CoachMarkStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachMarkStep: Anchor<CGRect>],
                       nextValue: () -> [CoachMarkStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func coachMarkTarget(_ step: CoachMarkStep) -> some View {
        self.anchorPreference(key: CoachTargetKey.self, value: .bounds) { [step: $0] }
    }

    func coachMarkOverlay(for steps: Set<CoachMarkStep>) -> some View {
        self.overlayPreferenceValue(CoachTargetKey.self) { targets in
            CoachMarkOverlayView(targets: targets, activeSteps: steps)
        }
    }
}

// MARK: - Overlay

struct CoachMarkOverlayView: View {
    @EnvironmentObject var manager: CoachMarkManager
    let targets: [CoachMarkStep: Anchor<CGRect>]
    let activeSteps: Set<CoachMarkStep>

    var body: some View {
        GeometryReader { proxy in
            if let step = manager.currentStep, activeSteps.contains(step) {
                let targetRect: CGRect? = targets[step].map { proxy[$0] }

                ZStack {
                    if step.isInteractive {
                        interactiveDim(targetRect: targetRect)
                    } else {
                        blockingDim(targetRect: targetRect)
                    }

                    tooltip(step: step, targetRect: targetRect, in: proxy)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func interactiveDim(targetRect: CGRect?) -> some View {
        if let rect = targetRect {
            let padded = rect.insetBy(dx: -8, dy: -8)
            CutoutShape(cutout: padded, cornerRadius: 14)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .contentShape(CutoutShape(cutout: padded, cornerRadius: 14), eoFill: true)
        } else {
            Color.black.opacity(0.55)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func blockingDim(targetRect: CGRect?) -> some View {
        Color.black.opacity(0.55)
            .overlay {
                if let rect = targetRect {
                    RoundedRectangle(cornerRadius: 14)
                        .frame(width: rect.width + 16, height: rect.height + 16)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
    }

    private func tooltip(step: CoachMarkStep, targetRect: CGRect?, in proxy: GeometryProxy) -> some View {
        let card = VStack(alignment: .leading, spacing: 10) {
            Text(step.title).font(.headline)
            Text(step.message).font(.subheadline).foregroundStyle(.secondary)

            HStack {
                Button(L("coach.skip")) { manager.finish() }
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if !step.isInteractive {
                    Button {
                        manager.next()
                    } label: {
                        Text(step == .done ? L("coach.start") : L("tutorial.next")).bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 24)
        .allowsHitTesting(true)

        let pos = tooltipPosition(targetRect: targetRect, in: proxy)
        return card.position(pos)
    }

    private func tooltipPosition(targetRect: CGRect?, in proxy: GeometryProxy) -> CGPoint {
        let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
        guard let rect = targetRect else { return center }

        let cardHeight: CGFloat = 150
        let padding: CGFloat = 24

        if rect.midY < proxy.size.height / 2 {
            return CGPoint(x: center.x, y: rect.maxY + padding + cardHeight / 2)
        } else {
            return CGPoint(x: center.x, y: rect.minY - padding - cardHeight / 2)
        }
    }
}

// MARK: - Cutout Shape

struct CutoutShape: Shape {
    let cutout: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(
            in: cutout,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}
