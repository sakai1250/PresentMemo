import SwiftUI
import UniformTypeIdentifiers

struct DeckDetailView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    let deck: Deck

    @State private var editorMode: CardEditorMode?
    @State private var pendingDeleteCard: Flashcard?
    @State private var editingNoteIndex: Int? = nil
    @State private var showCardCSVImporter = false
    @State private var cardImportMessage: String?
    @State private var showCardImportAlert = false

    var currentDeck: Deck { deckVM.decks.first { $0.id == deck.id } ?? deck }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress header
                VStack(spacing: 8) {
                    ProgressRing(progress: currentDeck.progressRatio, size: 80)
                    Text("\(currentDeck.masteredCount) / \(currentDeck.cards.count) \(L("stats.mastered"))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12)).cornerRadius(16)
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    NavigationLink {
                        CardStudyView(deck: currentDeck)
                    } label: {
                        ActionButton(title: L("deck.study"), icon: "rectangle.stack", color: .blue)
                    }
                    NavigationLink {
                        QuizView(deck: currentDeck)
                    } label: {
                        ActionButton(title: L("deck.quiz"), icon: "questionmark.circle", color: .purple)
                    }
                    NavigationLink {
                        ListeningModeView(deck: currentDeck)
                    } label: {
                        ActionButton(title: L("deck.listen"), icon: "speaker.wave.2", color: .teal)
                    }
                    if !currentDeck.slideNotes.isEmpty {
                        NavigationLink {
                            RehearsalView(deck: currentDeck)
                        } label: {
                            ActionButton(title: L("deck.rehearsal"), icon: "play.rectangle", color: .orange)
                        }
                    }
                }
                .padding(.horizontal)

                // Slide notes list
                if !currentDeck.slideNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("deck.slide_notes"))
                            .font(.headline).padding(.horizontal)

                        ForEach(Array(currentDeck.slideNotes.enumerated()), id: \.offset) { index, note in
                            SlideNoteRow(
                                index: index,
                                note: note,
                                imageData: index < currentDeck.slideImageData.count ? currentDeck.slideImageData[index] : nil,
                                onEdit: { editingNoteIndex = index }
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                // Cards list
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(L("deck.cards_count") |> { String(format: $0, currentDeck.cards.count) })")
                            .font(.headline)
                        Spacer()
                        Menu {
                            Button {
                                showCardCSVImporter = true
                            } label: {
                                Label(L("csv.import"), systemImage: "square.and.arrow.down")
                            }
                            if !currentDeck.cards.isEmpty {
                                ShareLink(
                                    item: CSVService.exportFlashcards(currentDeck.cards),
                                    subject: Text(currentDeck.name),
                                    preview: SharePreview(currentDeck.name)
                                ) {
                                    Label(L("csv.export"), systemImage: "square.and.arrow.up")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)
                    if currentDeck.cards.isEmpty {
                        Text(L("deck.empty_cards"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(currentDeck.cards) { card in
                            CardRow(
                                card: card,
                                onEdit: { editorMode = .edit(card) },
                                onDelete: { pendingDeleteCard = card }
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(currentDeck.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorMode = .create
                } label: {
                    Label(L("deck.add_card"), systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            CardEditorSheet(mode: mode) { term, definition, example in
                switch mode {
                case .create:
                    let newCard = Flashcard(
                        term: term,
                        definition: definition,
                        example: example
                    )
                    deckVM.addCard(newCard, toDeck: currentDeck.id)
                case .edit(let card):
                    var updated = card
                    updated.term = term
                    updated.definition = definition
                    updated.example = example
                    deckVM.updateCard(updated, inDeck: currentDeck.id)
                }
            }
        }
        .alert(
            L("deck.delete_card"),
            isPresented: Binding(
                get: { pendingDeleteCard != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteCard = nil }
                }
            ),
            presenting: pendingDeleteCard
        ) { card in
            Button(L("button.cancel"), role: .cancel) { pendingDeleteCard = nil }
            Button(L("button.delete"), role: .destructive) {
                deckVM.deleteCard(card.id, fromDeck: currentDeck.id)
                pendingDeleteCard = nil
            }
        } message: { _ in
            Text(L("deck.delete_card_confirm"))
        }
        .sheet(item: Binding(
            get: { editingNoteIndex.map { SlideNoteEditItem(index: $0) } },
            set: { editingNoteIndex = $0?.index }
        )) { item in
            SlideNoteEditorSheet(
                index: item.index,
                initialText: item.index < currentDeck.slideNotes.count ? currentDeck.slideNotes[item.index] : ""
            ) { newText in
                var updated = currentDeck
                while updated.slideNotes.count <= item.index {
                    updated.slideNotes.append("")
                }
                updated.slideNotes[item.index] = newText
                updated.updatedAt = Date()
                deckVM.update(updated)
            }
        }
        .fileImporter(
            isPresented: $showCardCSVImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleCardCSVImport(result)
        }
        .alert(cardImportMessage ?? "", isPresented: $showCardImportAlert) {
            Button(L("button.close"), role: .cancel) { }
        }
    }

    private func handleCardCSVImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let cards = CSVService.parseFlashcards(from: content)
        if cards.isEmpty {
            cardImportMessage = L("csv.no_data")
        } else {
            deckVM.addCards(cards, toDeck: currentDeck.id)
            cardImportMessage = String(format: L("csv.imported_cards"), cards.count)
        }
        showCardImportAlert = true
    }
}

private enum CardEditorMode: Identifiable {
    case create
    case edit(Flashcard)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let card):
            return card.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .create:
            return L("deck.add_card")
        case .edit:
            return L("deck.edit_card")
        }
    }
}

private struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mode: CardEditorMode
    let onSave: (String, String, String) -> Void

    @State private var term: String
    @State private var definition: String
    @State private var example: String

    init(mode: CardEditorMode, onSave: @escaping (String, String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _term = State(initialValue: "")
            _definition = State(initialValue: "")
            _example = State(initialValue: "")
        case .edit(let card):
            _term = State(initialValue: card.term)
            _definition = State(initialValue: card.definition)
            _example = State(initialValue: card.example)
        }
    }

    var canSave: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("label.term"), text: $term)
                TextField(L("label.definition"), text: $definition, axis: .vertical)
                    .lineLimit(3...6)
                TextField(L("label.example"), text: $example, axis: .vertical)
                    .lineLimit(2...4)
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("button.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("button.save")) {
                        onSave(
                            term.trimmingCharacters(in: .whitespacesAndNewlines),
                            definition.trimmingCharacters(in: .whitespacesAndNewlines),
                            example.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

// Simple pipe-forward operator for formatting
infix operator |>: AdditionPrecedence
func |><A, B>(a: A, f: (A) -> B) -> B { f(a) }

struct ActionButton: View {
    let title: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(title).font(.caption).bold().foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(color.opacity(0.12)).cornerRadius(14)
    }
}

struct CardRow: View {
    let card: Flashcard
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.term).font(.subheadline).bold()
                Text(card.definition).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            MasteryDot(level: card.masteryLevel)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.primary.opacity(0.03)).cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

struct MasteryDot: View {
    let level: MasteryLevel
    var color: Color {
        switch level {
        case .new: return .gray
        case .learning: return .red
        case .reviewing: return .yellow
        case .mastered: return .green
        }
    }
    var body: some View {
        Circle().fill(color).frame(width: 10, height: 10)
    }
}

// MARK: - Slide Note Editing

private struct SlideNoteEditItem: Identifiable {
    let index: Int
    var id: Int { index }
}

struct SlideNoteRow: View {
    let index: Int
    let note: String
    let imageData: Data?
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            #if canImport(UIKit)
            if let data = imageData, !data.isEmpty, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 42)
                    .cornerRadius(6)
            } else {
                slideIndexPlaceholder
            }
            #else
            slideIndexPlaceholder
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: L("scoring.slide_number"), index + 1))
                    .font(.subheadline).bold()
                Text(note.isEmpty ? L("deck.slide_notes_empty") : note)
                    .font(.caption)
                    .foregroundStyle(note.isEmpty ? .tertiary : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.primary.opacity(0.03)).cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    private var slideIndexPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 56, height: 42)
            .overlay(Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary))
    }
}

private struct SlideNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let index: Int
    let onSave: (String) -> Void

    @State private var text: String

    init(index: Int, initialText: String, onSave: @escaping (String) -> Void) {
        self.index = index
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle(String(format: L("scoring.slide_number"), index + 1))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("button.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("button.save")) {
                            onSave(text)
                            dismiss()
                        }
                    }
                }
        }
    }
}
