import Foundation
import PDFKit
import NaturalLanguage
import Vision
import CoreGraphics

class PDFAnalyzer {
    private let useSemanticRerank = false

    func extractPageTexts(from url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            pages.append(extractText(from: page))
        }
        return pages
    }

    func extractText(from url: URL) -> String {
        extractPageTexts(from: url).joined(separator: "\n")
    }

    /// Returns (term, context, score) tuples sorted by importance + MLP reranking.
    func extractKeyTerms(from text: String, max: Int = 50) async -> [(term: String, context: String, score: Double)] {
        let sourceText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let normalizedText = sourceText.replacingOccurrences(of: "\n", with: " ")
        var freq: [String: Int] = [:]

        // 1) Named-entity / lexical tagger (Noun Chunks 抽出)
        print("🔍 PDFAnalyzer: NLTagger 形態素解析(文節チャンク化) 開始 (テキスト長: \(normalizedText.count)文字)...")
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = normalizedText
        
        var currentChunkTokens: [String] = []
        var lastEndIndex: String.Index?
        
        let saveChunk = {
            guard !currentChunkTokens.isEmpty else { return }
            let term = currentChunkTokens.joined(separator: " ") // 英語ならスペース区切り、日本語なら元のままになるよう後で調整
                .trimmingCharacters(in: .whitespaces)
            // 連続する和文名詞の間の不要なスペースを消す(簡易的)
            let joinedTerm = term.replacingOccurrences(of: #"([ぁ-んァ-ン一-龥])\s+([ぁ-んァ-ン一-龥])"#, with: "$1$2", options: .regularExpression)
            
            let cleaned = self.sanitizePhrase(joinedTerm)
            // 複数単語なら有用なフレーズか、単語なら有用な単語か判定
            let isMulti = currentChunkTokens.count > 1
            if (isMulti && self.isUsefulPhrase(cleaned)) || (!isMulti && self.isUsefulToken(cleaned)) {
                let weight = isMulti ? 3 : (cleaned.count > 4 ? 2 : 1) // 長い句や単語を優遇
                freq[cleaned, default: 0] += weight
            }
            currentChunkTokens.removeAll()
        }

        tagger.enumerateTags(in: normalizedText.startIndex..<normalizedText.endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitPunctuation]) { tag, range in
            let w = String(normalizedText[range])
            // 空白スキップ
            if w.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
            
            if let t = tag, (t == .noun || t == .adjective || t == .organizationName || t == .personalName || t == .placeName) {
                if let lastEnd = lastEndIndex, lastEnd <= range.lowerBound {
                    let textBetween = normalizedText[lastEnd..<range.lowerBound]
                    if textBetween.trimmingCharacters(in: .whitespaces).isEmpty {
                        currentChunkTokens.append(w)
                    } else {
                        saveChunk()
                        currentChunkTokens = [w]
                    }
                } else {
                    saveChunk()
                    currentChunkTokens = [w]
                }
                lastEndIndex = range.upperBound
            } else {
                saveChunk()
                lastEndIndex = nil
            }
            return true
        }
        saveChunk()

        // 2) Pattern-based multi-word terms
        print("🔍 PDFAnalyzer: 正規表現パターン解析 開始...")
        let patterns = [
            "\\b[A-Z][a-zA-Z]+-[a-zA-Z]+\\b",   // hyphenated terms
            "\\b[A-Z]{2,6}\\b",                   // acronyms
            "\\b[a-zA-Z]{3,} [a-zA-Z]{3,}\\b",   // technical bigrams
        ]
        for pat in patterns {
            if let re = try? NSRegularExpression(pattern: pat) {
                let ns = normalizedText as NSString
                re.enumerateMatches(in: normalizedText, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    if let m = m {
                        let w = ns.substring(with: m.range)
                        let cleaned = sanitizePhrase(w)
                        if isUsefulPhrase(cleaned) { freq[cleaned, default: 0] += 2 }
                    }
                }
            }
        }

        let importantCandidates = freq
            .filter { $0.value >= 2 }
            .map { (term: $0.key, freq: $0.value, score: importanceScore(term: $0.key, frequency: $0.value, in: sourceText)) }
            .sorted { $0.score > $1.score }
            .prefix(100)
        
        let rankedAll: [(term: String, score: Double)]
        if useSemanticRerank {
            print("🔍 PDFAnalyzer: 候補絞り込み完了 (候補数: \(importantCandidates.count))。CoreML意味解析へ移行します...")
            let semanticInput = importantCandidates.map { (key: $0.term, value: $0.freq) }
            rankedAll = await rerankBySemanticSimilarity(candidates: Array(semanticInput), document: sourceText)
        } else {
            print("⚡️ PDFAnalyzer: semantic rerank OFF（重要度ランキング）")
            rankedAll = importantCandidates
                .map { (term: $0.term, score: $0.score) }
        }

        let ranked = diversifyCandidates(from: rankedAll, limit: max)

        // スコア付きの候補リストを構築
        var scoredResults = ranked
            .map { (term: $0.term, context: snippet(for: $0.term, in: sourceText), score: $0.score) }
            .filter { !$0.context.isEmpty }

        // MLP重み付けリランク（学習済みモデルがあれば）
        if KeywordMLPService.shared.hasTrainedModel {
            print("🧠 PDFAnalyzer: MLP重み付けリランク実行中...")
            scoredResults = KeywordMLPService.shared.rerankCandidates(
                candidates: scoredResults,
                sourceText: sourceText
            )
            print("✅ PDFAnalyzer: MLPリランク完了")
        }

        return scoredResults
    }

    private func rerankBySemanticSimilarity(
        candidates: [(key: String, value: Int)],
        document: String
    ) async -> [(term: String, score: Double)] {
        guard !candidates.isEmpty else { return [] }

        // CoreML Sentence-BERT モデルによる文全体のベクトル取得
        let docVector: [Float]?
        do {
            print("🚀 CoreML: 文全体(1000文字)の埋め込みベクトル取得開始...")
            // 劇的な遅延を回避：swift-transformersは全テキストを走査してしまうため、
            // 最大128トークンしか食わないSBERTの仕様に合わせて先頭1000文字のみ抜き出してベクトル化する
            let docPrefix = String(document.prefix(1000))
            docVector = try await KeyBERTService.shared.getSentenceEmbedding(text: docPrefix)
            print("✅ CoreML: 文全体の埋め込みベクトル取得成功！")
        } catch {
            print("⚠️ CoreML: 文全体の埋め込みに失敗: \(error)")
            docVector = nil
        }
        
        // フォールバック: モデルがロードできない場合は頻度のみでソート
        let docEmbedding = docVector
        
        var ranked: [(term: String, score: Double)] = []
        ranked.reserveCapacity(candidates.count)

        // Swift Concurrencyの「スレッド枯渇（デッドロック）」を防ぐため、
        // 直列実行に戻しつつ、毎回のCoreML呼び出し後にスレッドを解放（Task.yield()）します。
        // これによりUIの停止を防ぎます。
        let total = candidates.count
        var count = 0
        for candidate in candidates {
            count += 1
            if count % 10 == 0 || count == 1 {
                print("🔄 CoreML: \(count)/\(total) 件目の候補を推論中... (\(candidate.key))")
            }
            let frequencyScore = Double(candidate.value)
            
            if let v = try? await KeyBERTService.shared.getSentenceEmbedding(text: candidate.key),
               let validDocEmbedding = docEmbedding {
                let similarity = KeyBERTService.shared.cosineSimilarity(a: v, b: validDocEmbedding)
                let semanticScore = Double(similarity)
                let finalScore = semanticScore * 8.0 + frequencyScore
                ranked.append((candidate.key, finalScore))
            } else {
                ranked.append((candidate.key, frequencyScore))
            }
            // 協調的マルチタスク機構を利用して他のスレッド（UI等）に処理を譲る
            await Task.yield()
        }

        print("✅ CoreML: 全候補データの推論完了！ランキングのソート処理を実行します。")
        return ranked.sorted { $0.score > $1.score }
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    private func snippet(for term: String, in text: String) -> String {
        let sentences = splitIntoSentences(text)
        for s in sentences {
            let lower = s.lowercased()
            if lower.contains(term.lowercased()), isUsefulContext(s, term: term) {
                return s
            }
        }
        return ""
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { line -> [String] in
                line
                    .split(whereSeparator: { ".!?".contains($0) })
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { $0.count >= 24 }
    }

    private func isUsefulContext(_ context: String, term: String) -> Bool {
        let lower = context.lowercased()
        guard lower.contains(term.lowercased()) else { return false }
        if lower.contains("@") || lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
            return false
        }
        if lower.range(of: #"\b(doi|arxiv|copyright|all rights reserved|et al\.?)\b"#, options: .regularExpression) != nil {
            return false
        }
        if lower.range(of: #"\b(university|institute|laboratory|inc\.?|corp\.?|corporation|ltd\.?|llc|gmbh)\b"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func extractText(from page: PDFPage) -> String {
        let native = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !native.isEmpty { return native }
        if let cgImage = renderPageImage(page: page) {
            return recognizeText(from: cgImage).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func renderPageImage(page: PDFPage, targetWidth: CGFloat = 1600) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = targetWidth / bounds.width
        let width = Int(targetWidth)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // PDF coordinates are bottom-left origin, so flip for rendering.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    private func recognizeText(from image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "ja-JP"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: " ")
        } catch {
            return ""
        }
    }

    private func sanitizeToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private func sanitizePhrase(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func importanceScore(term: String, frequency: Int, in text: String) -> Double {
        let lowerText = text.lowercased()
        let lowerTerm = term.lowercased()
        guard !lowerTerm.isEmpty else { return 0 }

        let nsText = lowerText as NSString
        let nsTerm = lowerTerm as NSString
        var range = NSRange(location: 0, length: nsText.length)
        var firstLoc: Int?
        var hits = 0

        while true {
            let found = nsText.range(of: nsTerm as String, options: [], range: range)
            if found.location == NSNotFound { break }
            if firstLoc == nil { firstLoc = found.location }
            hits += 1
            let next = found.location + found.length
            if next >= nsText.length { break }
            range = NSRange(location: next, length: nsText.length - next)
        }

        let tf = log1p(Double(max(hits, frequency))) * 2.2
        let wordCount = term.split(separator: " ").count
        let phraseBonus = min(Double(max(wordCount - 1, 0)) * 0.9, 2.7)
        let acronymBonus: Double = term.range(of: #"^[A-Z0-9\-]{2,}$"#, options: .regularExpression) != nil ? 0.8 : 0
        let lengthBonus = min(Double(term.count) / 18.0, 1.0)
        let positionBonus: Double
        if let firstLoc, nsText.length > 0 {
            let ratio = Double(firstLoc) / Double(nsText.length)
            positionBonus = max(0, 1.2 - ratio * 1.2)
        } else {
            positionBonus = 0
        }

        return tf + phraseBonus + acronymBonus + lengthBonus + positionBonus
    }

    private func diversifyCandidates(from ranked: [(term: String, score: Double)], limit: Int) -> [(term: String, score: Double)] {
        guard limit > 0 else { return [] }
        var selected: [(term: String, score: Double)] = []
        selected.reserveCapacity(limit)

        for candidate in ranked {
            if selected.count >= limit { break }
            let isNearDuplicate = selected.contains { existing in
                areTermsSimilar(candidate.term, existing.term)
            }
            if !isNearDuplicate {
                selected.append(candidate)
            }
        }

        return selected
    }

    private func areTermsSimilar(_ a: String, _ b: String) -> Bool {
        let na = normalizedTermTokens(a)
        let nb = normalizedTermTokens(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }

        let sa = Set(na)
        let sb = Set(nb)

        if sa == sb { return true }

        let intersection = sa.intersection(sb).count
        let minCount = min(sa.count, sb.count)
        if minCount > 0 {
            let overlap = Double(intersection) / Double(minCount)
            if overlap >= 1.0 { return true }               // subset match (e.g. head / multi-head)
            if overlap >= 0.8 && abs(sa.count - sb.count) <= 1 { return true }
        }

        let ca = na.joined()
        let cb = nb.joined()
        if ca == cb { return true }                         // model / models after stemming
        if abs(ca.count - cb.count) <= 1 && (ca.hasPrefix(cb) || cb.hasPrefix(ca)) { return true }

        return false
    }

    private func normalizedTermTokens(_ term: String) -> [String] {
        let lower = term.lowercased().replacingOccurrences(of: "-", with: " ")
        let chunks = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return chunks
            .map(stemToken)
            .filter { $0.count >= 2 }
    }

    private func stemToken(_ token: String) -> String {
        if token.hasSuffix("ies"), token.count > 4 {
            return String(token.dropLast(3) + "y")
        }
        if token.hasSuffix("es"), token.count > 4 {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("s"), token.count > 3 {
            return String(token.dropLast())
        }
        return token
    }

    private func isUsefulToken(_ token: String) -> Bool {
        guard token.count >= 3 else { return false }
        guard token.rangeOfCharacter(from: .letters) != nil else { return false }
        if token.range(of: #"^\d+$"#, options: .regularExpression) != nil { return false }
        if token.contains("@") || token.contains("/") { return false }
        return !stopWords.contains(token.lowercased())
    }

    private func isUsefulPhrase(_ phrase: String) -> Bool {
        // スペースで区切ってチェック、もしくは和文ならそのままチェック
        let words = phrase.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            // 英語系のフレーズ
            return words.allSatisfy { isUsefulToken(String($0)) }
        } else {
            // 結合された和文フレーズなど
            return isUsefulToken(phrase) && phrase.count >= 3
        }
    }

    private var stopWords: Set<String> {
        [
            "the", "and", "for", "with", "from", "that", "this", "are", "was", "were",
            "have", "has", "had", "using", "used", "into", "than", "then", "also",
            "our", "their", "your", "its", "can", "may", "might", "will", "shall",
            "not", "but", "such", "via", "per", "between", "within",
            "author", "authors", "affiliation", "affiliations", "university", "department",
            "institute", "laboratory", "copyright", "references", "appendix",
            "figure", "table", "email", "supplementary", "acknowledgements"
        ]
    }
}
