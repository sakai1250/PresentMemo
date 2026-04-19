import SwiftUI

struct ContentView: View {
    @EnvironmentObject var deckVM: DeckViewModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label(L("tab.home"), systemImage: "house.fill") }
            DeckListView()
                .tabItem { Label(L("tab.decks"), systemImage: "books.vertical.fill") }
            SettingsView()
                .tabItem { Label(L("tab.settings"), systemImage: "gearshape.fill") }
        }
    }
}

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
