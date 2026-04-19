import SwiftUI

@main
struct PresentMemoApp: App {
    @StateObject private var deckVM = DeckViewModel()

    init() {
        NotificationManager.shared.requestPermission()
        UserDefaults.standard.register(defaults: [
            "ai.enabled": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deckVM)
        }
    }
}
