import SwiftUI

@main
struct PresentMemoApp: App {
    @StateObject private var deckVM = DeckViewModel()
    @StateObject private var coachMarkManager = CoachMarkManager()

    init() {
        UserDefaults.standard.register(defaults: [
            "ai.enabled": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deckVM)
                .environmentObject(coachMarkManager)
        }
    }
}
