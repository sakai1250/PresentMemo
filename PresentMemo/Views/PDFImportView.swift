import SwiftUI
import UniformTypeIdentifiers
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

enum PDFImportPurpose {
    case paperAnalysis
    case slideRehearsal
}

struct PDFImportView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @Environment(\.dismiss) private var dismiss

    var purpose: PDFImportPurpose = .paperAnalysis
    var targetDeckId: UUID?
    var initialDeckName: String = ""
    var onComplete: (() -> Void)? = nil

    @State private var showPicker = false
    @State private var analyzing = false
    @State private var results: [(term: String, context: String, score: Double)] = []
    @State private var selected: Set<String> = []
    @State private var slideTexts: [String] = []
    @State private var slideImageData: [Data] = []
    @State private var slideDeckName: String = ""
    @State private var errorMsg: String?
    @State private var isTraining = false
    @State private var trainingProgress: Float = 0
    @State private var lastSourceText: String = ""
    @State private var analysisProgress: Double = 0
    @State private var analysisStatus: String = ""
    private let enableAIExtraction = true

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 20) {
                    if analyzing {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                                    .frame(width: 100, height: 100)
                                Circle()
                                    .trim(from: 0, to: analysisProgress)
                                    .stroke(
                                        AngularGradient(
                                            colors: [.blue, .cyan, .blue],
                                            center: .center
                                        ),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 0.3), value: analysisProgress)
                                Text("\(Int(analysisProgress * 100))%")
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                            Text(analysisStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                    } else if isSlideMode {
                        slideModeContent
                    } else {
                        paperModeContent
                    }
                }
                .navigationTitle(isSlideMode ? L("pdf.slide_import_title") : L("pdf.import_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(L("button.cancel")) { dismiss() }
                    }
                    if (!results.isEmpty && !isSlideMode) || (!slideTexts.isEmpty && isSlideMode) {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(L("pdf.select")) { showPicker = true }
                        }
                    }
                }
                .fileImporter(isPresented: $showPicker,
                              allowedContentTypes: [.pdf],
                              allowsMultipleSelection: false) { result in
                    handleFileResult(result)
                }
                .alert("Error", isPresented: .constant(errorMsg != nil)) {
                    Button("OK") { errorMsg = nil }
                } message: { Text(errorMsg ?? "") }
                .onAppear {
                    if slideDeckName.isEmpty {
                        slideDeckName = initialDeckName
                    }
                }
            }

            // MLP学習中オーバーレイ
            if isTraining {
                TrainingOverlayView(
                    progress: trainingProgress,
                    sessionCount: KeywordMLPService.shared.sessionCount + 1
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }

    private var isSlideMode: Bool { purpose == .slideRehearsal }

    @ViewBuilder
    private var paperModeContent: some View {
        if results.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 60))
                    .foregroundStyle(.red)
                Text(L("pdf.select_prompt"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Button(L("pdf.select")) { showPicker = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results, id: \.term) { item in
                Toggle(isOn: Binding(
                    get: { selected.contains(item.term) },
                    set: { if $0 { selected.insert(item.term) } else { selected.remove(item.term) } }
                )) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.term).font(.subheadline).bold()
                            Text(item.context).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if KeywordMLPService.shared.hasTrainedModel {
                            Text(String(format: "%.0f%%", item.score * 100))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [.cyan, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            Button(action: importSelected) {
                Text(String(format: "%@ (%d)", L("pdf.import_selected"), selected.count))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(selected.isEmpty || isTraining)
            .padding()
        }
    }

    @ViewBuilder
    private var slideModeContent: some View {
        if slideTexts.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.on.rectangle.angled.fill").font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text(L("pdf.slide_select_prompt"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Button(L("pdf.select")) { showPicker = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section(header: Text(L("create.deck.name"))) {
                    TextField(L("deck.new_name"), text: $slideDeckName)
                }
                Section(header: Text(String(format: L("pptx.slides_found"), slideTexts.count))) {
                    ForEach(slideTexts.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Slide \(i + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(slideTexts[i].isEmpty ? "(no text)" : slideTexts[i])
                                .font(.subheadline)
                                .lineLimit(3)
                        }
                    }
                }
            }

            Button(L("pdf.create_rehearsal_deck")) { importSlideDeck() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
        }
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            analyzing = true
            analysisProgress = 0
            analysisStatus = L("pdf.analyzing")
            Task {
                let startedAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if startedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                print("==== ⏱️ [開始] PDF読み込み解析 ====")
                let totalStartTime = CFAbsoluteTimeGetCurrent()
                
                let analyzer = PDFAnalyzer()
                if isSlideMode {
                    await updateProgress(0.05, status: L("pdf.step.extracting_text"))
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let pages = analyzer.extractPageTexts(from: url)
                    print("⏱️ [1] PDFテキスト抽出完了: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))秒")
                    
                    let normalizedPages = pages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    
                    await updateProgress(0.15, status: L("pdf.step.rendering_images"))
                    let t1 = CFAbsoluteTimeGetCurrent()
                    let pageImages = renderSlideImages(from: url)
                    print("⏱️ [2] PDF画像レンダリング完了: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t1))秒")
                    
                    let joined = normalizedPages.joined(separator: "\n\n")
                    
                    await updateProgress(0.30, status: L("pdf.step.extracting_keywords"))
                    let t2 = CFAbsoluteTimeGetCurrent()
                    let localTerms = await analyzer.extractKeyTerms(from: joined, max: 80)
                    print("⏱️ [3] PDFAnalyzer(CoreML等) 重要単語抽出: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t2))秒")
                    
                    let aiTerms: [(term: String, context: String)]
                    if enableAIExtraction {
                        await updateProgress(0.60, status: L("pdf.step.ai_analysis"))
                        let t3 = CFAbsoluteTimeGetCurrent()
                        aiTerms = await AIExtractionService.shared.extractTermContextPairs(
                            from: joined,
                            max: 80,
                            domain: .presentation
                        )
                        print("⏱️ [4] AIサービス 重要単語抽出: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t3))秒")
                    } else {
                        aiTerms = []
                        print("⚡️ [4] AIサービス 重要単語抽出: OFF")
                    }

                    await updateProgress(0.90, status: L("pdf.step.finalizing"))
                    let terms = mergeTerms(ai: aiTerms, local: localTerms)
                    
                    await MainActor.run {
                        analysisProgress = 1.0
                        slideTexts = normalizedPages
                        slideImageData = pageImages
                        results = terms
                        lastSourceText = joined
                        selected = Set(terms.prefix(30).map { $0.term })
                        if slideDeckName.isEmpty {
                            slideDeckName = L("mode.pptx")
                        }
                        analyzing = false
                    }
                } else {
                    await updateProgress(0.05, status: L("pdf.step.extracting_text"))
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let text = analyzer.extractText(from: url)
                    print("⏱️ [1] PDFテキスト抽出全体完了: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))秒")
                    
                    await updateProgress(0.20, status: L("pdf.step.extracting_keywords"))
                    let t1 = CFAbsoluteTimeGetCurrent()
                    let localTerms = await analyzer.extractKeyTerms(from: text)
                    print("⏱️ [2] PDFAnalyzer(CoreML等) 重要単語抽出: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t1))秒")
                    
                    let aiTerms: [(term: String, context: String)]
                    if enableAIExtraction {
                        await updateProgress(0.55, status: L("pdf.step.ai_analysis"))
                        let t2 = CFAbsoluteTimeGetCurrent()
                        aiTerms = await AIExtractionService.shared.extractTermContextPairs(from: text, max: 80)
                        print("⏱️ [3] AIサービス 重要単語抽出: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t2))秒")
                    } else {
                        aiTerms = []
                        print("⚡️ [3] AIサービス 重要単語抽出: OFF")
                    }

                    await updateProgress(0.90, status: L("pdf.step.finalizing"))
                    let terms = mergeTerms(ai: aiTerms, local: localTerms)
                    await MainActor.run {
                        analysisProgress = 1.0
                        results = terms
                        lastSourceText = text
                        selected = Set(terms.prefix(10).map { $0.term })
                        analyzing = false
                    }
                }
                print("==== ⏱️ [完了] PDF読み込み合計時間: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - totalStartTime))秒 ====")
            }
        case .failure(let e):
            errorMsg = e.localizedDescription
        }
    }

    @MainActor
    private func updateProgress(_ value: Double, status: String) {
        analysisProgress = value
        analysisStatus = status
    }

    private func importSelected() {
        let chosen = results.filter { selected.contains($0.term) }
        let allCandidates = results
        let sourceText = lastSourceText

        Task {
            // 1. MLP学習フェーズ
            await MainActor.run {
                isTraining = true
                trainingProgress = 0
            }

            await KeywordMLPService.shared.learnFromSelection(
                allCandidates: allCandidates,
                selectedTerms: selected,
                sourceText: sourceText,
                progressCallback: { progress in
                    trainingProgress = progress
                }
            )

            await MainActor.run {
                isTraining = false
            }

            // 2. インポートフェーズ
            await MainActor.run { analyzing = true }
            let newCards = await buildCardsWithJapaneseTranslation(from: chosen)
            await MainActor.run {
                if let id = targetDeckId {
                    deckVM.addCards(newCards, toDeck: id)
                } else {
                    let deck = Deck(name: L("mode.pdf"), mode: .pdfAnalysis, cards: newCards)
                    deckVM.add(deck)
                    onComplete?()
                }
                analyzing = false
                dismiss()
            }
        }
    }

    private func importSlideDeck() {
        let finalName = slideDeckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("mode.pptx")
            : slideDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allCandidates = results
        let sourceText = lastSourceText

        Task {
            // 1. MLP学習フェーズ（候補がある場合のみ）
            if !allCandidates.isEmpty {
                await MainActor.run {
                    isTraining = true
                    trainingProgress = 0
                }

                await KeywordMLPService.shared.learnFromSelection(
                    allCandidates: allCandidates,
                    selectedTerms: selected,
                    sourceText: sourceText,
                    progressCallback: { progress in
                        trainingProgress = progress
                    }
                )

                await MainActor.run {
                    isTraining = false
                }
            }

            // 2. インポートフェーズ
            await MainActor.run { analyzing = true }
            let cards: [Flashcard]
            if !results.isEmpty {
                cards = await buildCardsWithJapaneseTranslation(from: Array(results.prefix(40)))
            } else {
                cards = slideTexts.enumerated().map { i, text in
                    Flashcard(term: "Slide \(i + 1)", definition: text.isEmpty ? "Slide \(i + 1)" : text)
                }
            }

            await MainActor.run {
                let deck = Deck(
                    name: finalName,
                    mode: .powerPoint,
                    cards: cards,
                    slideTexts: slideTexts,
                    slideNotes: slideTexts,
                    slideImageData: slideImageData
                )
                deckVM.add(deck)
                onComplete?()
                analyzing = false
                dismiss()
            }
        }
    }

    private func buildCardsWithJapaneseTranslation(
        from items: [(term: String, context: String, score: Double)]
    ) async -> [Flashcard] {
        print("==== ⏱️ [開始] 翻訳処理（並列） ====")
        let t0 = CFAbsoluteTimeGetCurrent()
        // 並列処理（並行HTTPリクエスト）で翻訳を取得して劇的に高速化
        let res = await withTaskGroup(of: (Int, Flashcard).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let baseContext = item.context.trimmingCharacters(in: .whitespacesAndNewlines)
                    let translated = await TranslationService.shared.translateTermToJapanese(item.term)
                    
                    if let ja = translated, !ja.isEmpty, ja.lowercased() != item.term.lowercased() {
                        return (index, Flashcard(term: item.term, definition: ja, example: baseContext))
                    } else {
                        return (index, Flashcard(term: item.term, definition: baseContext.isEmpty ? item.term : baseContext))
                    }
                }
            }
            
            var results: [(Int, Flashcard)] = []
            for await r in group { results.append(r) }
            
            // 元の配列順序を復元
            return results.sorted { $0.0 < $1.0 }.map { $1 }
        }
        print("==== ⏱️ [完了] 翻訳処理合計時間: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))秒 ====")
        return res
    }

    private func mergeTerms(
        ai: [(term: String, context: String)],
        local: [(term: String, context: String, score: Double)]
    ) -> [(term: String, context: String, score: Double)] {
        var merged: [(term: String, context: String, score: Double)] = []
        var seen: Set<String> = []

        // Prefer deterministic local extraction first; use AI as supplemental only.
        // localにはスコアが付いている。aiにはスコアがないので0.0をデフォルトにする。
        let localItems = local.map { (term: $0.term, context: $0.context, score: $0.score) }
        let aiItems = ai.map { (term: $0.term, context: $0.context, score: 0.0) }

        for item in localItems + aiItems {
            let term = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = item.context.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            guard isAcceptableContext(context, term: term) else { continue }
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append((term: term, context: context.isEmpty ? term : context, score: item.score))
            if merged.count >= 80 { break }
        }
        return merged
    }

    private func isAcceptableContext(_ context: String, term: String) -> Bool {
        let text = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 10 else { return false }
        let lower = text.lowercased()
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

    private func renderSlideImages(from url: URL) -> [Data] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var images: [Data] = []
        images.reserveCapacity(doc.pageCount)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
#if canImport(UIKit)
            let image = page.thumbnail(of: CGSize(width: 1280, height: 720), for: .mediaBox)
            if let data = image.jpegData(compressionQuality: 0.82) {
                images.append(data)
            } else {
                images.append(Data())
            }
#else
            images.append(Data())
#endif
        }
        return images
    }
}
