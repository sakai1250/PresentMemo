import SwiftUI
import UniformTypeIdentifiers

struct PPTXImportView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @Environment(\.dismiss) private var dismiss
    var onComplete: (() -> Void)? = nil

    @State private var showPicker = false
    @State private var importing  = false
    @State private var slides: [PPTXParser.Slide] = []
    @State private var aiPairs: [(term: String, context: String)] = []
    @State private var deckName   = ""
    @State private var errorMsg: String?
    @State private var showPDFFallback = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if importing {
                    ProgressView(L("pptx.importing")).padding(40)
                } else if slides.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle.angled.fill")
                            .font(.system(size: 60)).foregroundStyle(.orange)
                        Text(L("pptx.select_prompt"))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        Button(L("pptx.select")) { showPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        if hasLowTextExtraction {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("pptx.low_text_hint"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button(L("pptx.open_pdf_ocr")) {
                                    showPDFFallback = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }

                        Form {
                            Section(header: Text(L("create.deck.name"))) {
                                TextField(L("deck.new_name"), text: $deckName)
                            }
                            Section(header: Text(String(format: L("pptx.slides_found"), slides.count))) {
                                ForEach(slides.indices, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Slide \(i + 1)").font(.caption).foregroundStyle(.secondary)
                                        Text(slides[i].bodyText.isEmpty ? "(no text)" : slides[i].bodyText)
                                            .font(.subheadline).lineLimit(2)
                                        if !slides[i].notes.isEmpty {
                                            Text(slides[i].notes).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                        Button(L("button.save")) { saveDecks() }
                            .buttonStyle(.borderedProminent).controlSize(.large).padding()
                    }
                }
            }
            .navigationTitle(L("pptx.import_title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("button.cancel")) { dismiss() }
                }
                if !slides.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L("pptx.select")) { showPicker = true }
                    }
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [UTType(filenameExtension: "pptx") ?? .data],
                          allowsMultipleSelection: false) { result in
                handleFile(result)
            }
            .alert("Error", isPresented: .constant(errorMsg != nil)) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
            .sheet(isPresented: $showPDFFallback) {
                PDFImportView(onComplete: onComplete)
            }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importing = true
            Task {
                do {
                    let _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    let parsed = try PPTXParser().parse(url: url)
                    let name = url.deletingPathExtension().lastPathComponent
                    let presentationText = parsed.enumerated().map { i, slide in
                        """
                        Slide \(i + 1)
                        Body: \(slide.bodyText)
                        Notes: \(slide.notes)
                        """
                    }.joined(separator: "\n\n")
                    let ai = await AIExtractionService.shared.extractTermContextPairs(
                        from: presentationText,
                        max: 120,
                        domain: .presentation
                    )
                    await MainActor.run {
                        slides    = parsed
                        aiPairs   = ai
                        deckName  = name
                        importing = false
                    }
                } catch {
                    await MainActor.run {
                        errorMsg  = error.localizedDescription
                        importing = false
                    }
                }
            }
        case .failure(let e):
            errorMsg = e.localizedDescription
        }
    }

    private func saveDecks() {
        let finalName = deckName.isEmpty ? L("mode.pptx") : deckName
        let cards: [Flashcard]
        if !aiPairs.isEmpty {
            cards = aiPairs.map { pair in
                Flashcard(term: pair.term, definition: pair.context)
            }
        } else {
            // Fallback: create flashcards from slide notes/body.
            cards = slides.enumerated().map { i, s in
                Flashcard(term: "Slide \(i + 1)", definition: s.notes.isEmpty ? s.bodyText : s.notes)
            }
        }
        let deck = Deck(
            name: finalName,
            mode: .powerPoint,
            cards: cards,
            slideTexts: slides.map { $0.bodyText },
            slideNotes: slides.map { $0.notes }
        )
        deckVM.add(deck)
        onComplete?()
        dismiss()
    }

    private var hasLowTextExtraction: Bool {
        let nonEmptyCount = slides.filter {
            !$0.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return !slides.isEmpty && nonEmptyCount <= max(1, slides.count / 4)
    }
}
