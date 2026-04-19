import Foundation

/// External tokenizer dependencies are intentionally avoided to keep builds stable.
/// This service provides a lightweight local tokenizer fallback for CoreML inputs.
actor CoreMLTokenizerService {
    static let shared = CoreMLTokenizerService()

    private init() {}

    /// テキストをトークナイズし、CoreMLに入力可能な形状(Int32配列)にして返す
    /// NOTE:
    /// - This is a deterministic fallback tokenizer.
    /// - It is not equivalent to HF WordPiece/BPE, but keeps local extraction working.
    func tokenize(text: String, modelName: String, maxLength: Int) async throws -> (inputIds: [Int32], attentionMask: [Int32]) {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let pieces = normalized.split { $0.isWhitespace || $0.isPunctuation }.map(String.init)

        // Mimic common transformer layout: [CLS] ...tokens... [SEP]
        let clsId: Int32 = 101
        let sepId: Int32 = 102
        let padId: Int32 = 0

        var inputIds: [Int32] = [clsId]
        inputIds.append(contentsOf: pieces.map(stableTokenId))
        inputIds.append(sepId)

        var attentionMask = Array(repeating: Int32(1), count: inputIds.count)

        // パディング & 切り詰め処理
        if inputIds.count > maxLength {
            inputIds = Array(inputIds.prefix(maxLength))
            attentionMask = Array(attentionMask.prefix(maxLength))
        } else if inputIds.count < maxLength {
            let paddingCount = maxLength - inputIds.count
            inputIds.append(contentsOf: Array(repeating: padId, count: paddingCount))
            attentionMask.append(contentsOf: Array(repeating: Int32(0), count: paddingCount))
        }

        return (inputIds, attentionMask)
    }

    private func stableTokenId(for piece: String) -> Int32 {
        if piece.isEmpty { return 0 }
        // Reserve low IDs for special tokens and keep token range bounded.
        var hasher = Hasher()
        hasher.combine(piece)
        let raw = hasher.finalize()
        let bucket = abs(raw % 30000) + 1000
        return Int32(bucket)
    }
}
