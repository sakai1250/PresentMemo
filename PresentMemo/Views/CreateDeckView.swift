import SwiftUI

struct CreateDeckView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: AppMode = .default
    @State private var deckName = ""
    @State private var showPDF  = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("create.deck.name"))) {
                    TextField(L("deck.new_name"), text: $deckName)
                }
                Section(header: Text("Mode")) {
                    modeOptionRow(.default)
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
        }
    }

    private func create() {
        switch selectedMode {
        case .default:
            let deck = Deck(name: deckName.isEmpty ? L("mode.default") : deckName,
                            mode: .default,
                            cards: DefaultVocabulary.cards)
            deckVM.add(deck)
            dismiss()
        case .pdfAnalysis:
            showPDF = true
        case .powerPoint:
            showPDF = true
        }
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
        .onTapGesture { selectedMode = mode }
    }

    func modeColor(_ m: AppMode) -> Color {
        switch m {
        case .default: return .blue
        case .pdfAnalysis: return .red
        case .powerPoint: return .orange
        }
    }
}
