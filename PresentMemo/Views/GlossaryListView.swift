import SwiftUI
import UniformTypeIdentifiers

struct GlossaryListView: View {
    @ObservedObject private var manager = GlossaryManager.shared
    @State private var editingTerm: GlossaryTerm?
    @State private var showAddSheet = false
    @State private var showFileImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    var body: some View {
        List {
            if manager.terms.isEmpty {
                Text(L("glossary.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(manager.terms) { term in
                    Button {
                        editingTerm = term
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(term.english).font(.subheadline).bold()
                                .foregroundStyle(.primary)
                            Text(term.japanese).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    manager.delete(at: offsets)
                }
            }
        }
        .navigationTitle(L("glossary.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label(L("glossary.import"), systemImage: "square.and.arrow.down")
                    }
                    if !manager.terms.isEmpty {
                        ShareLink(
                            item: CSVService.exportGlossary(manager.terms),
                            subject: Text(L("glossary.title")),
                            preview: SharePreview(L("glossary.title"))
                        ) {
                            Label(L("glossary.export"), systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            GlossaryTermEditorSheet(term: nil) { english, japanese in
                manager.add(GlossaryTerm(english: english, japanese: japanese))
            }
        }
        .sheet(item: $editingTerm) { term in
            GlossaryTermEditorSheet(term: term) { english, japanese in
                var updated = term
                updated.english = english
                updated.japanese = japanese
                manager.update(updated)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(importMessage ?? "", isPresented: $showImportAlert) {
            Button(L("button.close"), role: .cancel) { }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = CSVService.parseGlossary(from: content)
        if parsed.isEmpty {
            importMessage = L("csv.no_data")
        } else {
            let count = manager.importTerms(parsed)
            importMessage = String(format: L("glossary.imported"), count)
        }
        showImportAlert = true
    }
}

// MARK: - Editor Sheet

private struct GlossaryTermEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let term: GlossaryTerm?
    let onSave: (String, String) -> Void

    @State private var english: String
    @State private var japanese: String

    init(term: GlossaryTerm?, onSave: @escaping (String, String) -> Void) {
        self.term = term
        self.onSave = onSave
        _english = State(initialValue: term?.english ?? "")
        _japanese = State(initialValue: term?.japanese ?? "")
    }

    private var canSave: Bool {
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !japanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("glossary.english"), text: $english)
                    .autocorrectionDisabled()
                TextField(L("glossary.japanese"), text: $japanese)
            }
            .navigationTitle(term == nil ? L("glossary.add") : L("glossary.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("button.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("button.save")) {
                        onSave(
                            english.trimmingCharacters(in: .whitespacesAndNewlines),
                            japanese.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
