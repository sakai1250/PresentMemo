import Foundation
import CoreML
import Accelerate
import NaturalLanguage

final class KeyBERTService: @unchecked Sendable {
    static let shared = KeyBERTService()
    
    // CoreML生成されたクラスが存在する前提（Xcodeが自動生成します）
    // lazy var sbertModel = try? SentenceBERT(configuration: MLModelConfiguration())
    
    private let textModelName = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    // Performance experiment: disable embedding-based rerank and use n-gram ranking only.
    private let useSemanticRerank = true
    private let maxCandidateLength = 100
    private let minCandidateLength = 2
    private let defaultCandidateLimit = 100
    
    // キャッシュされたCoreMLモデルとスレッドセーフ化のためのロック
    private var sbertModel: MLModel?
    private let modelLock = NSLock()
    
    private init() {}
    
    private func loadModelIfNeeded() throws -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        if let model = sbertModel { return model }
        guard let modelURL = Bundle.main.url(forResource: "SentenceBERT", withExtension: "mlmodelc") else {
            throw KeyBERTError.modelNotLoaded
        }
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly // SimulatorのGPU/MPSクラッシュを回避
        #else
        config.computeUnits = .cpuAndNeuralEngine
        #endif
        
        let loadedModel = try MLModel(contentsOf: modelURL, configuration: config)
        self.sbertModel = loadedModel
        return loadedModel
    }
    
    /// セリフの中から重要単語(キーワード)をN件抽出します
    func extractKeywords(from speechText: String, topN: Int = 5) async throws -> [String] {
        // 1. 候補となる単語(N-gram)を生成
        let candidateLimit = max(12, min(60, topN * 10))
        let candidatePhrases = generateCandidates(from: speechText, limit: candidateLimit)
        guard !candidatePhrases.isEmpty else { return [] }

        // n-gram only mode (no CoreML inference)
        if !useSemanticRerank {
            return Array(candidatePhrases.prefix(topN))
        }

        // 2. 文全体をベクトル化
        let documentEmbedding = try await getSentenceEmbedding(text: speechText)

        // 3. 各候補をベクトル化し、文全体との類似度を計算
        var phraseScores: [(phrase: String, score: Float)] = []
        for phrase in candidatePhrases {
            if let phraseEmbedding = try? await getSentenceEmbedding(text: phrase) {
                let score = cosineSimilarity(a: documentEmbedding, b: phraseEmbedding)
                phraseScores.append((phrase, score))
            }
        }

        // 4. スコア順にソートして上位N件を返す
        phraseScores.sort { $0.score > $1.score }
        return Array(phraseScores.prefix(topN).map { $0.phrase })
    }
    
    /// Apple標準の形態素解析（NLTokenizer）を用いて名詞等のキーワード候補を抽出
    private func generateCandidates(from text: String, limit: Int = 36) -> [String] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        var frequency: [String: Int] = [:]
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = normalized
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        tagger.enumerateTags(in: normalized.startIndex..<normalized.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            if let tag = tag {
                // KeyBERTの候補として、名詞(noun)を中心に収集
                if tag == .noun || tag == .organizationName || tag == .personalName || tag == .placeName {
                    let word = String(normalized[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isUsefulCandidate(word) {
                        frequency[word, default: 0] += 1
                    }
                }
            }
            return true
        }
        
        if frequency.isEmpty { return [] }
        let hardLimit = max(8, min(120, limit == 36 ? defaultCandidateLimit : limit))
        return frequency
            .sorted {
                if $0.value == $1.value {
                    return $0.key.count < $1.key.count
                }
                return $0.value > $1.value
            }
            .prefix(hardLimit)
            .map(\.key)
    }

    private func isUsefulCandidate(_ word: String) -> Bool {
        guard word.count >= minCandidateLength, word.count <= maxCandidateLength else { return false }
        if word.allSatisfy({ $0.isNumber }) { return false }
        if word.contains("@") || word.contains("http://") || word.contains("https://") || word.contains("www.") {
            return false
        }
        return true
    }
    
    func getSentenceEmbedding(text: String) async throws -> [Float] {
        let maxLen = 128
        let tokens = try await CoreMLTokenizerService.shared.tokenize(text: text, modelName: textModelName, maxLength: maxLen)
        
        let inputIdsMulti = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        let attnMaskMulti = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        
        for i in 0..<maxLen {
            inputIdsMulti[i] = NSNumber(value: tokens.inputIds[i])
            attnMaskMulti[i] = NSNumber(value: tokens.attentionMask[i])
        }
        
        let model = try loadModelIfNeeded()
        
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsMulti),
            "attention_mask": MLFeatureValue(multiArray: attnMaskMulti)
        ])
        
        let output = try await model.prediction(from: featureProvider)
        guard let textEmbeds = output.featureValue(for: "sentence_embedding")?.multiArrayValue else {
            throw KeyBERTError.inferenceFailed
        }
        
        return toFloatArray(textEmbeds)
    }
    
    private func toFloatArray(_ multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var floats = [Float](repeating: 0, count: count)
        for i in 0..<count {
            floats[i] = multiArray[i].floatValue
        }
        return floats
    }
    
    func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        guard a.count == b.count, a.count > 0 else { return 0.0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        let count = vDSP_Length(a.count)
        
        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)
        vDSP_svesq(a, 1, &normA, count)
        vDSP_svesq(b, 1, &normB, count)
        
        let denominator = sqrt(normA) * sqrt(normB)
        if denominator == 0 { return 0.0 }
        return dotProduct / denominator
    }
}

enum KeyBERTError: Error {
    case modelNotLoaded
    case inferenceFailed
}
