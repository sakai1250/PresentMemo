import SwiftUI

struct DeckListView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(deckVM.decks) { deck in
                    NavigationLink { DeckDetailView(deck: deck) } label: {
                        DeckRowCard(deck: deck)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onDelete(perform: deckVM.delete)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(StudyTheme.background)
            .navigationTitle(L("tab.decks"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreate) { CreateDeckView() }
        }
    }
}
