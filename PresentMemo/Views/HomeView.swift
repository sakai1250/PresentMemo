import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @EnvironmentObject var coachMark: CoachMarkManager
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Welcome
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("home.welcome")).font(.title2).bold()
                        Text(L("home.subtitle")).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.horizontal)

                    // Stats row
                    if !deckVM.decks.isEmpty {
                        HStack(spacing: 12) {
                            StatPill(value: "\(deckVM.decks.count)",  label: L("stats.decks"),   icon: "books.vertical.fill",  color: .blue)
                            StatPill(value: "\(totalCards)",          label: L("stats.cards"),   icon: "rectangle.stack.fill", color: .orange)
                            StatPill(value: "\(totalMastered)",       label: L("stats.mastered"),icon: "checkmark.seal.fill",  color: .green)
                        }.padding(.horizontal)
                    }

                    // Learning chart
                    if totalCards > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("home.stats_chart_title"))
                                .font(.headline)
                            Chart(masteryData) { item in
                                BarMark(
                                    x: .value(L("home.stats_chart_x"), item.label),
                                    y: .value(L("home.stats_chart_y"), item.count)
                                )
                                .foregroundStyle(item.color.gradient)
                                .annotation(position: .top) {
                                    Text("\(item.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(height: 190)
                            .chartYAxis { AxisMarks(position: .leading) }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(14)
                        .padding(.horizontal)
                    }

                    // Recent decks
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("home.recent")).font(.headline).padding(.horizontal)
                        if deckVM.decks.isEmpty {
                            Text(L("home.empty"))
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).padding(40)
                        } else {
                            ForEach(deckVM.decks.prefix(3)) { deck in
                                NavigationLink { DeckDetailView(deck: deck) } label: {
                                    DeckRowCard(deck: deck)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                                .transformAnchorPreference(key: CoachTargetKey.self, value: .bounds) { dict, anchor in
                                    if deck.id == deckVM.decks.first?.id {
                                        dict[.tapDeck] = anchor
                                    }
                                }
                            }
                        }
                    }

                    // Mode cards
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("home.new_deck")).font(.headline).padding(.horizontal)
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            ModeCard(mode: mode) { showCreate = true }
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L("app.name"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .coachMarkTarget(.tapCreate)
                }
            }
            .sheet(isPresented: $showCreate) { CreateDeckView() }
            .onChange(of: showCreate) { _, isShowing in
                if isShowing {
                    coachMark.advance(from: .tapCreate)
                }
            }
            .onChange(of: deckVM.decks.count) { oldCount, newCount in
                if newCount > oldCount {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        coachMark.advance(from: .tapSave)
                    }
                }
            }
        }
    }

    var totalCards:   Int { deckVM.decks.reduce(0) { $0 + $1.cards.count } }
    var totalMastered: Int { deckVM.decks.reduce(0) { $0 + $1.masteredCount } }
    var allCards: [Flashcard] { deckVM.decks.flatMap(\.cards) }
    var masteryData: [MasteryChartItem] {
        let grouped = Dictionary(grouping: allCards, by: \.masteryLevel)
        return MasteryLevel.allCases.map { level in
            MasteryChartItem(level: level, count: grouped[level, default: []].count)
        }
    }
}

struct MasteryChartItem: Identifiable {
    let level: MasteryLevel
    let count: Int

    var id: String { level.rawValue }
    var label: String { level.label }
    var color: Color {
        switch level {
        case .new: return .gray
        case .learning: return .red
        case .reviewing: return .yellow
        case .mastered: return .green
        }
    }
}

struct StatPill: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title2).bold()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(color.opacity(0.1)).cornerRadius(12)
    }
}

struct ModeCard: View {
    let mode: AppMode; let action: () -> Void
    var modeColor: Color {
        switch mode {
        case .default: return .blue
        case .manualInput: return .teal
        case .csvImport: return .indigo
        case .pdfAnalysis: return .red
        case .powerPoint: return .orange
        }
    }
    var desc: String {
        switch mode {
        case .default: return L("mode.default.desc")
        case .manualInput: return L("mode.manual.desc")
        case .csvImport: return L("mode.csv.desc")
        case .pdfAnalysis: return L("mode.pdf.desc")
        case .powerPoint: return L("mode.pptx.desc")
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.iconName)
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(modeColor).cornerRadius(12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.localizedName).font(.subheadline).bold().foregroundStyle(.primary)
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }
}

struct DeckRowCard: View {
    let deck: Deck
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deck.mode.iconName)
                .font(.title3).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(modeColor).cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name).font(.subheadline).bold()
                Text(String(format: L("deck.cards_count"), deck.cards.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(progress: deck.progressRatio, size: 32)
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
    var modeColor: Color {
        switch deck.mode {
        case .default: return .blue
        case .manualInput: return .teal
        case .csvImport: return .indigo
        case .pdfAnalysis: return .red
        case .powerPoint: return .orange
        }
    }
}

struct ProgressRing: View {
    let progress: Double; let size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 3)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%").font(.system(size: size * 0.28)).bold()
        }
        .frame(width: size, height: size)
        .animation(.easeInOut, value: progress)
    }
}
