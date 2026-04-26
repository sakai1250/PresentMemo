import SwiftUI
import UniformTypeIdentifiers

struct CreateDeckView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @EnvironmentObject var coachMark: CoachMarkManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: AppMode = .default
    @State private var deckName = ""
    @State private var showPDF = false
    @State private var showCSVImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("create.deck.name"))) {
                    TextField(L("deck.new_name"), text: $deckName)
                }
                Section(header: Text("Mode")) {
                    modeOptionRow(.default)
                    modeOptionRow(.manualInput)
                    modeOptionRow(.csvImport)
                    modeOptionRow(.pdfAnalysis)
                    modeOptionRow(.powerPoint)
                }
            }
            .navigationTitle(L("create.deck.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("button.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("button.save")) { create() }
                        .bold()
                        .coachMarkTarget(.tapSave)
                }
            }
            .sheet(isPresented: $showPDF) {
                PDFImportView(
                    purpose: selectedMode == .powerPoint ? .slideRehearsal : .paperAnalysis,
                    initialDeckName: deckName,
                    onComplete: {
                        dismiss()
                    }
                )
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImport(result)
            }
            .alert(importMessage ?? "", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button(L("button.close"), role: .cancel) { }
            }
        }
        .coachMarkOverlay(for: [.selectManual, .tapSave])
    }

    private func create() {
        let trimmedName = deckName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch selectedMode {
        case .default:
            let deck = Deck(
                name: trimmedName.isEmpty ? L("deck.default.name") : trimmedName,
                mode: .default,
                cards: DefaultVocabulary.cards
            )
            deckVM.add(deck)
            dismiss()

        case .manualInput:
            let deck = Deck(
                name: trimmedName.isEmpty ? L("deck.manual.name") : trimmedName,
                mode: .manualInput,
                cards: []
            )
            deckVM.add(deck)
            dismiss()

        case .csvImport:
            showCSVImporter = true

        case .pdfAnalysis:
            showPDF = true

        case .powerPoint:
            showPDF = true
        }
    }

    private func handleCSVImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
            importMessage = L("csv.no_data")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            importMessage = L("csv.no_data")
            return
        }

        let cards = CSVService.parseFlashcards(from: content)
        guard !cards.isEmpty else {
            importMessage = L("csv.no_data")
            return
        }

        let trimmedName = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = Deck(
            name: trimmedName.isEmpty ? L("deck.csv.name") : trimmedName,
            mode: .csvImport,
            cards: cards
        )
        deckVM.add(deck)
        dismiss()
    }

    @ViewBuilder
    private func modeOptionRow(_ mode: AppMode) -> some View {
        HStack {
            Image(systemName: mode.iconName).foregroundStyle(modeColor(mode))
            Text(mode.localizedName)
            Spacer()
            if selectedMode == mode {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMode = mode
            if mode == .manualInput {
                coachMark.advance(from: .selectManual)
            }
        }
        .transformAnchorPreference(key: CoachTargetKey.self, value: .bounds) { dict, anchor in
            if mode == .manualInput {
                dict[.selectManual] = anchor
            }
        }
    }

    func modeColor(_ m: AppMode) -> Color {
        switch m {
        case .default: return .blue
        case .manualInput: return .teal
        case .csvImport: return .indigo
        case .pdfAnalysis: return .red
        case .powerPoint: return .orange
        }
    }
}
