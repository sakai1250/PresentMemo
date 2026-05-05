import SwiftUI

struct ContentView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @EnvironmentObject var coachMark: CoachMarkManager
    @State private var selectedTab = 0
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showBrandSplash = true

    var body: some View {
        ZStack {
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

            if showBrandSplash {
                BrandSplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .coachMarkOverlay(for: [.tapCreate, .tapDeck, .addCard, .done])
        .onAppear {
            if onboardingCompleted {
                coachMark.startIfNeeded()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showBrandSplash = false
                }
            }
        }
        .onChange(of: coachMark.requestedTab) { _, tab in
            if let tab {
                selectedTab = tab
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            StartView {
                onboardingCompleted = true
                coachMark.startIfNeeded()
            } onOpenTutorial: {
                onboardingCompleted = true
                coachMark.restart()
            }
        }
    }
}

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

private struct BrandSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.13, blue: 0.22), Color(red: 0.06, green: 0.09, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                (
                    Text("M")
                    + Text("AI").foregroundStyle(.red)
                    + Text("ORAL")
                )
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                Text("Memorize + AI + Oral")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(24)
        }
    }
}

private struct StartView: View {
    let onStart: () -> Void
    let onOpenTutorial: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L("start.title"))
                        .font(.largeTitle.bold())
                    Text(L("start.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        featureCard(
                            title: L("tutorial.page1.title"),
                            body: L("tutorial.page1.body"),
                            icon: "square.grid.2x2.fill",
                            color: .teal
                        )
                        featureCard(
                            title: L("tutorial.page2.title"),
                            body: L("tutorial.page2.body"),
                            icon: "rectangle.stack.fill",
                            color: .blue
                        )
                        featureCard(
                            title: L("tutorial.page3.title"),
                            body: L("tutorial.page3.body"),
                            icon: "speaker.wave.2.fill",
                            color: .orange
                        )
                        featureCard(
                            title: L("tutorial.page4.title"),
                            body: L("tutorial.page4.body"),
                            icon: "bell.badge.fill",
                            color: .indigo
                        )
                    }

                    Button(action: onStart) {
                        Text(L("start.cta"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: onOpenTutorial) {
                        Text(L("start.tutorial_cta"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(20)
            }
            .navigationTitle(L("app.name"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func featureCard(title: String, body: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
