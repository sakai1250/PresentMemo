import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RehearsalView: View {
    @StateObject private var vm: RehearsalViewModel

    init(deck: Deck) {
        _vm = StateObject(wrappedValue: RehearsalViewModel(deck: deck))
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.totalSlides == 0 {
                Spacer()
                Text(L("rehearsal.no_slides")).foregroundStyle(.secondary)
                Spacer()
            } else if vm.complete {
                completeView
            } else {
                slideArea
                controlBar
            }
        }
        .navigationTitle(L("rehearsal.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { timerSettings }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.startScoring() } label: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
                .disabled(vm.scorableSlideCount == 0 || vm.scoringInProgress)
            }
        }
        .overlay {
            if vm.scoringInProgress {
                scoringProgressOverlay
            }
        }
        .sheet(isPresented: $vm.scoringMode) {
            ScoringResultView(
                slideScores: vm.slideScores,
                averageScore: vm.averageScore,
                deck: vm.deck,
                onDismiss: { vm.dismissScoring() }
            )
        }
        .alert(L("scoring.no_scorable_slides"), isPresented: Binding(
            get: { vm.scoringError != nil },
            set: { if !$0 { vm.scoringError = nil } }
        )) {
            Button(L("button.close"), role: .cancel) { }
        }
    }

    // MARK: Slide area
    private var slideArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Slide counter
                Text("\(vm.slideIndex + 1) / \(vm.totalSlides)")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)

                // Slide card (image-first)
#if canImport(UIKit)
                if let data = vm.currentSlideImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.03))
                        .cornerRadius(12)
                } else {
                    Text(vm.currentBodyText.isEmpty ? "Slide \(vm.slideIndex + 1)" : vm.currentBodyText)
                        .font(.title3).bold()
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(16)
                }
#else
                Text(vm.currentBodyText.isEmpty ? "Slide \(vm.slideIndex + 1)" : vm.currentBodyText)
                    .font(.title3).bold()
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(16)
#endif

                // Notes reveal
                VStack(alignment: .leading, spacing: 10) {
                    switch vm.phase {
                    case .slide:
                        Text(L("rehearsal.phase.slide"))
                            .font(.subheadline).foregroundStyle(.secondary).italic()
                    case .keywords:
                        Text(L("rehearsal.phase.keywords")).font(.subheadline).bold()
                        FlowLayout(items: vm.keywords) { kw in
                            Text(kw)
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.blue.opacity(0.15)).cornerRadius(20)
                        }
                    case .fullText:
                        Text(L("rehearsal.phase.full")).font(.subheadline).bold()
                        Text(vm.currentNotes).font(.body)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .animation(.easeInOut(duration: 0.4), value: vm.phase)
            }
            .padding()
        }
    }

    // MARK: Control bar
    private var controlBar: some View {
        HStack(spacing: 20) {
            Button { vm.prevSlide() } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(vm.slideIndex > 0 ? .primary : .tertiary)
            }.disabled(vm.slideIndex == 0)

            Spacer()

            if !vm.running {
                Button {
                    if vm.slideIndex == 0 && vm.phase == .slide { vm.start() }
                    else { vm.resume() }
                } label: {
                    Label(vm.slideIndex == 0 ? L("rehearsal.start") : L("rehearsal.resume"),
                          systemImage: "play.fill")
                        .font(.headline).padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.green).foregroundStyle(.white).cornerRadius(24)
                }
            } else {
                Button { vm.pause() } label: {
                    Label(L("rehearsal.pause"), systemImage: "pause.fill")
                        .font(.headline).padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.orange).foregroundStyle(.white).cornerRadius(24)
                }
            }

            Spacer()

            Button { vm.nextSlide() } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2).foregroundStyle(.primary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
    }

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "star.fill").font(.system(size: 60)).foregroundStyle(.yellow)
            Text(L("rehearsal.complete")).font(.title).bold()
            Button(L("study.restart")) { vm.restart() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
    }

    private var scoringProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: Double(vm.scoringProgress))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)

                Text(L("scoring.analyzing"))
                    .font(.headline).foregroundStyle(.white)

                Text(String(format: L("scoring.progress"),
                            Int(vm.scoringProgress * Float(vm.scorableSlideCount)),
                            vm.scorableSlideCount))
                    .font(.caption).foregroundStyle(.white.opacity(0.7))

                Button(L("button.cancel")) { vm.cancelScoring() }
                    .buttonStyle(.bordered).tint(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }

    private var timerSettings: some View {
        Menu {
            VStack {
                Text(L("rehearsal.slide_delay"))
                Picker("", selection: $vm.slideDelay) {
                    ForEach([3.0, 5.0, 7.0, 10.0], id: \.self) { v in
                        Text(String(format: L("rehearsal.seconds"), v)).tag(v)
                    }
                }
            }
        } label: {
            Image(systemName: "timer")
        }
    }
}

/// Simple horizontal flow layout for keyword chips
struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        var rows: [[Item]] = [[]]
        for item in items {
            rows[rows.count - 1].append(item)
            if rows[rows.count - 1].count >= 4 { rows.append([]) }
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 6) {
                        ForEach(rows[rowIdx], id: \.self) { item in
                            content(item)
                        }
                    }
                }
            }
        )
    }
}
