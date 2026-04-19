import Foundation
import Accelerate

// MARK: - Feature Extractor

/// キーワード候補から8次元の特徴量ベクトルを生成する
struct KeywordFeatureExtractor {

    /// 特徴量を抽出する。sourceTextは元のPDFテキスト全体。
    static func extract(
        term: String,
        context: String,
        importanceScore: Double,
        sourceText: String
    ) -> [Float] {
        let lowerTerm = term.lowercased()
        let lowerSource = sourceText.lowercased()

        // 1. 単語数 (正規化: /10)
        let words = term.split(separator: " ").count
        let wordCount = Float(words) / 10.0

        // 2. 文字数 (正規化: /50)
        let charCount = Float(term.count) / 50.0

        // 3. 出現頻度 (log正規化)
        let freq = countOccurrences(of: lowerTerm, in: lowerSource)
        let frequency = log1p(Float(freq)) / 5.0

        // 4. 初出位置比率 (前方ほど1.0に近い)
        let positionRatio: Float
        if let range = lowerSource.range(of: lowerTerm) {
            let offset = lowerSource.distance(from: lowerSource.startIndex, to: range.lowerBound)
            positionRatio = 1.0 - Float(offset) / max(Float(lowerSource.count), 1.0)
        } else {
            positionRatio = 0.0
        }

        // 5. 大文字略語か (0 or 1)
        let isAcronym: Float = term.range(of: #"^[A-Z0-9\-]{2,}$"#, options: .regularExpression) != nil ? 1.0 : 0.0

        // 6. ハイフン付き複合語か (0 or 1)
        let hasHyphen: Float = term.contains("-") ? 1.0 : 0.0

        // 7. コンテキスト文の長さ (正規化: /300)
        let contextLength = min(Float(context.count) / 300.0, 1.0)

        // 8. 既存の重要度スコア (正規化: /20)
        let importance = min(Float(importanceScore) / 20.0, 1.0)

        return [wordCount, charCount, frequency, positionRatio, isAcronym, hasHyphen, contextLength, importance]
    }

    private static func countOccurrences(of target: String, in text: String) -> Int {
        guard !target.isEmpty else { return 0 }
        let nsText = text as NSString
        var range = NSRange(location: 0, length: nsText.length)
        var count = 0
        while true {
            let found = nsText.range(of: target, options: [], range: range)
            if found.location == NSNotFound { break }
            count += 1
            let next = found.location + found.length
            if next >= nsText.length { break }
            range = NSRange(location: next, length: nsText.length - next)
        }
        return count
    }
}

// MARK: - MLP Model

/// 3層全結合ニューラルネットワーク (8 → 16 → 8 → 1)
/// Accelerate (vDSP) で行列演算を高速化
struct KeywordMLP: Codable {
    // 重み行列 (row-major)
    var w1: [Float]   // 16 x 8 = 128
    var b1: [Float]   // 16
    var w2: [Float]   // 8 x 16 = 128
    var b2: [Float]   // 8
    var w3: [Float]   // 1 x 8 = 8
    var b3: [Float]   // 1

    static let inputDim = 8
    static let hidden1Dim = 16
    static let hidden2Dim = 8
    static let outputDim = 1

    /// Xavier初期化で新規モデルを作成
    init() {
        w1 = Self.xavierInit(fanIn: Self.inputDim, fanOut: Self.hidden1Dim)
        b1 = [Float](repeating: 0, count: Self.hidden1Dim)
        w2 = Self.xavierInit(fanIn: Self.hidden1Dim, fanOut: Self.hidden2Dim)
        b2 = [Float](repeating: 0, count: Self.hidden2Dim)
        w3 = Self.xavierInit(fanIn: Self.hidden2Dim, fanOut: Self.outputDim)
        b3 = [Float](repeating: 0, count: Self.outputDim)
    }

    private static func xavierInit(fanIn: Int, fanOut: Int) -> [Float] {
        let limit = sqrt(6.0 / Float(fanIn + fanOut))
        return (0..<(fanIn * fanOut)).map { _ in Float.random(in: -limit...limit) }
    }

    // MARK: - Forward Pass

    /// 予測（0〜1のスコアを返す）
    func predict(features: [Float]) -> Float {
        let h1 = relu(addBias(matVecMul(w1, features, rows: Self.hidden1Dim, cols: Self.inputDim), b1))
        let h2 = relu(addBias(matVecMul(w2, h1, rows: Self.hidden2Dim, cols: Self.hidden1Dim), b2))
        let out = addBias(matVecMul(w3, h2, rows: Self.outputDim, cols: Self.hidden2Dim), b3)
        return sigmoid(out[0])
    }

    /// バッチ予測
    func predictBatch(featuresBatch: [[Float]]) -> [Float] {
        featuresBatch.map { predict(features: $0) }
    }

    // MARK: - Training (SGD + Backprop)

    /// ミニバッチSGDで学習。progressCallbackはエポックごとに0.0〜1.0の進捗を報告。
    mutating func train(
        samples: [[Float]],
        labels: [Float],
        epochs: Int = 50,
        learningRate: Float = 0.01,
        progressCallback: ((Float) -> Void)? = nil
    ) {
        guard samples.count == labels.count, !samples.isEmpty else { return }

        for epoch in 0..<epochs {
            // シャッフルしたインデックス
            let indices = (0..<samples.count).shuffled()

            for idx in indices {
                let x = samples[idx]
                let label = labels[idx]

                // Forward
                let z1 = addBias(matVecMul(w1, x, rows: Self.hidden1Dim, cols: Self.inputDim), b1)
                let h1 = relu(z1)
                let z2 = addBias(matVecMul(w2, h1, rows: Self.hidden2Dim, cols: Self.hidden1Dim), b2)
                let h2 = relu(z2)
                let z3 = addBias(matVecMul(w3, h2, rows: Self.outputDim, cols: Self.hidden2Dim), b3)
                let yPred = sigmoid(z3[0])

                // Backward: dL/dy for BCE
                let dLdy = yPred - label  // derivative of BCE w.r.t. pre-sigmoid = yPred - label

                // Layer 3 gradients
                var dW3 = [Float](repeating: 0, count: Self.hidden2Dim)
                for j in 0..<Self.hidden2Dim {
                    dW3[j] = dLdy * h2[j]
                }
                let dB3 = dLdy

                // Backprop to h2
                var dH2 = [Float](repeating: 0, count: Self.hidden2Dim)
                for j in 0..<Self.hidden2Dim {
                    dH2[j] = dLdy * w3[j]
                }

                // ReLU grad for z2
                var dZ2 = [Float](repeating: 0, count: Self.hidden2Dim)
                for j in 0..<Self.hidden2Dim {
                    dZ2[j] = z2[j] > 0 ? dH2[j] : 0
                }

                // Layer 2 gradients
                var dW2 = [Float](repeating: 0, count: Self.hidden2Dim * Self.hidden1Dim)
                for i in 0..<Self.hidden2Dim {
                    for j in 0..<Self.hidden1Dim {
                        dW2[i * Self.hidden1Dim + j] = dZ2[i] * h1[j]
                    }
                }
                let dB2 = dZ2

                // Backprop to h1
                var dH1 = [Float](repeating: 0, count: Self.hidden1Dim)
                for j in 0..<Self.hidden1Dim {
                    for i in 0..<Self.hidden2Dim {
                        dH1[j] += dZ2[i] * w2[i * Self.hidden1Dim + j]
                    }
                }

                // ReLU grad for z1
                var dZ1 = [Float](repeating: 0, count: Self.hidden1Dim)
                for j in 0..<Self.hidden1Dim {
                    dZ1[j] = z1[j] > 0 ? dH1[j] : 0
                }

                // Layer 1 gradients
                var dW1 = [Float](repeating: 0, count: Self.hidden1Dim * Self.inputDim)
                for i in 0..<Self.hidden1Dim {
                    for j in 0..<Self.inputDim {
                        dW1[i * Self.inputDim + j] = dZ1[i] * x[j]
                    }
                }
                let dB1 = dZ1

                // SGD update
                let lr = learningRate
                for i in 0..<w1.count { w1[i] -= lr * dW1[i] }
                for i in 0..<b1.count { b1[i] -= lr * dB1[i] }
                for i in 0..<w2.count { w2[i] -= lr * dW2[i] }
                for i in 0..<b2.count { b2[i] -= lr * dB2[i] }
                for i in 0..<w3.count { w3[i] -= lr * dW3[i] }
                b3[0] -= lr * dB3
            }

            progressCallback?(Float(epoch + 1) / Float(epochs))
        }
    }

    // MARK: - Math Helpers

    private func matVecMul(_ mat: [Float], _ vec: [Float], rows: Int, cols: Int) -> [Float] {
        var result = [Float](repeating: 0, count: rows)
        // Accelerateの cblas_sgemv を利用
        vec.withUnsafeBufferPointer { vecBuf in
            mat.withUnsafeBufferPointer { matBuf in
                result.withUnsafeMutableBufferPointer { resBuf in
                    cblas_sgemv(
                        CblasRowMajor, CblasNoTrans,
                        Int32(rows), Int32(cols),
                        1.0,
                        matBuf.baseAddress!, Int32(cols),
                        vecBuf.baseAddress!, 1,
                        0.0,
                        resBuf.baseAddress!, 1
                    )
                }
            }
        }
        return result
    }

    private func addBias(_ vec: [Float], _ bias: [Float]) -> [Float] {
        var result = vec
        var b = bias
        vDSP_vadd(result, 1, b, 1, &result, 1, vDSP_Length(result.count))
        return result
    }

    private func relu(_ vec: [Float]) -> [Float] {
        var result = vec
        var zero: Float = 0
        vDSP_vthres(result, 1, &zero, &result, 1, vDSP_Length(result.count))
        return result
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}

// MARK: - Training History

/// 学習履歴のセッション単位（1回のPDF読み込み+選択 = 1セッション）
struct TrainingSession: Codable {
    let features: [[Float]]
    let labels: [Float]
    let date: Date
}

// MARK: - Service

/// MLPの学習・推論・永続化を管理するシングルトンサービス
final class KeywordMLPService {
    static let shared = KeywordMLPService()

    private var mlp: KeywordMLP
    private var history: [TrainingSession] = []
    private let maxHistorySessions = 20
    private let lock = NSLock()

    /// 学習済みモデルが存在するか
    var hasTrainedModel: Bool {
        FileManager.default.fileExists(atPath: Self.modelFilePath.path)
    }

    /// 学習セッション数
    var sessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return history.count
    }

    private init() {
        mlp = KeywordMLP()
        loadModel()
        loadHistory()
    }

    // MARK: - Rerank

    /// MLP予測スコアで候補を重み付け再ランキングする
    func rerankCandidates(
        candidates: [(term: String, context: String, score: Double)],
        sourceText: String
    ) -> [(term: String, context: String, score: Double)] {
        guard hasTrainedModel else { return candidates }

        lock.lock()
        let model = mlp
        lock.unlock()

        // 最大スコアで正規化用
        let maxOriginalScore = candidates.map { $0.score }.max() ?? 1.0
        let normalizer = maxOriginalScore > 0 ? maxOriginalScore : 1.0

        var reranked: [(term: String, context: String, score: Double)] = []
        reranked.reserveCapacity(candidates.count)

        for candidate in candidates {
            let features = KeywordFeatureExtractor.extract(
                term: candidate.term,
                context: candidate.context,
                importanceScore: candidate.score,
                sourceText: sourceText
            )
            let mlpScore = Double(model.predict(features: features))
            let normalizedOriginal = candidate.score / normalizer

            // 混合スコア: 0.3 * original + 0.7 * mlp
            let finalScore = 0.3 * normalizedOriginal + 0.7 * mlpScore

            reranked.append((term: candidate.term, context: candidate.context, score: finalScore))
        }

        return reranked.sorted { $0.score > $1.score }
    }

    // MARK: - Learn

    /// ユーザーの選択からMLPを学習する。progressCallbackでUI側に進捗を通知。
    func learnFromSelection(
        allCandidates: [(term: String, context: String, score: Double)],
        selectedTerms: Set<String>,
        sourceText: String,
        progressCallback: @escaping (Float) -> Void
    ) async {
        // 特徴量とラベルを構築
        var features: [[Float]] = []
        var labels: [Float] = []
        features.reserveCapacity(allCandidates.count)
        labels.reserveCapacity(allCandidates.count)

        for candidate in allCandidates {
            let feat = KeywordFeatureExtractor.extract(
                term: candidate.term,
                context: candidate.context,
                importanceScore: candidate.score,
                sourceText: sourceText
            )
            features.append(feat)
            labels.append(selectedTerms.contains(candidate.term) ? 1.0 : 0.0)
        }

        // 履歴に追加
        let session = TrainingSession(features: features, labels: labels, date: Date())

        lock.lock()
        history.append(session)
        // 最新N件のみ保持
        if history.count > maxHistorySessions {
            history = Array(history.suffix(maxHistorySessions))
        }

        // 全履歴を結合して学習データにする
        var allFeatures: [[Float]] = []
        var allLabels: [Float] = []
        for h in history {
            allFeatures.append(contentsOf: h.features)
            allLabels.append(contentsOf: h.labels)
        }

        // フレッシュなMLPを作成して全履歴から学習（累積学習）
        var newMLP = KeywordMLP()
        lock.unlock()

        // 学習（バックグラウンドスレッドで実行）
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                newMLP.train(
                    samples: allFeatures,
                    labels: allLabels,
                    epochs: 50,
                    learningRate: 0.01,
                    progressCallback: { progress in
                        DispatchQueue.main.async {
                            progressCallback(progress)
                        }
                    }
                )
                continuation.resume()
            }
        }

        lock.lock()
        mlp = newMLP
        lock.unlock()

        // 保存
        saveModel()
        saveHistory()

        print("✅ KeywordMLP: 学習完了 (全サンプル数: \(allFeatures.count), セッション数: \(history.count))")
    }

    // MARK: - Persistence

    private static var modelFilePath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("keyword_mlp_model.json")
    }

    private static var historyFilePath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("keyword_mlp_history.json")
    }

    private func saveModel() {
        lock.lock()
        let model = mlp
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(model)
            try data.write(to: Self.modelFilePath, options: .atomic)
            print("💾 KeywordMLP: モデル保存完了")
        } catch {
            print("⚠️ KeywordMLP: モデル保存失敗: \(error)")
        }
    }

    private func loadModel() {
        guard let data = try? Data(contentsOf: Self.modelFilePath),
              let model = try? JSONDecoder().decode(KeywordMLP.self, from: data) else {
            return
        }
        mlp = model
        print("📦 KeywordMLP: 学習済みモデル読み込み完了")
    }

    private func saveHistory() {
        lock.lock()
        let hist = history
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(hist)
            try data.write(to: Self.historyFilePath, options: .atomic)
        } catch {
            print("⚠️ KeywordMLP: 履歴保存失敗: \(error)")
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyFilePath),
              let hist = try? JSONDecoder().decode([TrainingSession].self, from: data) else {
            return
        }
        history = hist
        print("📦 KeywordMLP: 学習履歴読み込み完了 (セッション数: \(hist.count))")
    }
}
