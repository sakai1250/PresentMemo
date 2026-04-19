import SwiftUI

/// MLP学習中に表示するオーバーレイビュー
struct TrainingOverlayView: View {
    let progress: Float  // 0.0 ~ 1.0
    let sessionCount: Int

    @State private var pulseScale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var neuronOpacity: [Double] = Array(repeating: 0.3, count: 6)

    var body: some View {
        ZStack {
            // 半透明ブラー背景
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 28) {
                // ニューラルネットのアニメーション
                ZStack {
                    // 外側のリング
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    .purple.opacity(0.8),
                                    .blue.opacity(0.6),
                                    .cyan.opacity(0.8),
                                    .purple.opacity(0.8)
                                ]),
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(rotation))

                    // パルスする円
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .blue.opacity(0.3),
                                    .purple.opacity(0.15),
                                    .clear
                                ]),
                                center: .center,
                                startRadius: 10,
                                endRadius: 60
                            )
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(pulseScale)

                    // ニューロンノード
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .fill(Color.cyan.opacity(neuronOpacity[i]))
                            .frame(width: 10, height: 10)
                            .offset(neuronOffset(index: i, radius: 40))
                    }

                    // ブレインアイコン
                    Image(systemName: "brain")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(pulseScale)
                }

                // テキスト
                VStack(spacing: 8) {
                    Text("学習中...")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    if sessionCount > 0 {
                        Text("セッション \(sessionCount) の学習データを統合")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // プログレスバー
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // 背景
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.15))

                            // 進捗
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * CGFloat(progress)))
                                .animation(.easeInOut(duration: 0.15), value: progress)
                        }
                    }
                    .frame(height: 8)
                    .frame(maxWidth: 220)

                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }

                // エポック情報
                Text("Epoch \(Int(progress * 50)) / 50")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            )
        }
        .onAppear {
            startAnimations()
        }
    }

    private func neuronOffset(index: Int, radius: CGFloat) -> CGSize {
        let angle = Double(index) * (2 * .pi / 6.0) - .pi / 2
        return CGSize(
            width: cos(angle) * Double(radius),
            height: sin(angle) * Double(radius)
        )
    }

    private func startAnimations() {
        // パルスアニメーション
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
        }

        // リング回転
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rotation = 360
        }

        // ニューロンの明滅
        for i in 0..<6 {
            let delay = Double(i) * 0.2
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(delay)) {
                neuronOpacity[i] = 0.9
            }
        }
    }
}

#Preview {
    TrainingOverlayView(progress: 0.65, sessionCount: 3)
}
