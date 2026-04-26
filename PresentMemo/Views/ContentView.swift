import SwiftUI

struct ContentView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @StateObject private var coachMark = CoachMarkManager()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label(L("tab.home"), systemImage: "house.fill") }
                .tag(0)
            DeckListView()
                .tabItem { Label(L("tab.decks"), systemImage: "books.vertical.fill") }
                .tag(1)
            SettingsView()
                .tabItem { Label(L("tab.settings"), systemImage: "gearshape.fill") }
                .tag(2)
        }
        .environmentObject(coachMark)
        .onPreferenceChange(CoachMarkFrameKey.self) { frames in
            for (step, frame) in frames {
                coachMark.targetFrames[step] = frame
            }
        }
        .overlay {
            CoachMarkOverlay(manager: coachMark)
        }
        .onAppear {
            coachMark.startIfNeeded()
        }
        .onChange(of: coachMark.requestedTab) { _, tab in
            if let tab {
                selectedTab = tab
            }
        }
    }
}

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
