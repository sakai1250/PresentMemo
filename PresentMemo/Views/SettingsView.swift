import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @State private var showClearConfirm = false
    @AppStorage("notificationHours") private var notificationHours = 24
    @AppStorage("ai.enabled") private var aiEnabled = true

    let hourOptions = [0, 1, 3, 6, 12, 24, 48]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("settings.notifications"))) {
                    Picker(L("settings.notification_interval"), selection: $notificationHours) {
                        Text(L("settings.disabled")).tag(0)
                        ForEach(hourOptions.filter { $0 > 0 }, id: \.self) { h in
                            Text(String(format: L("settings.hours"), h)).tag(h)
                        }
                    }
                }

                Section(header: Text(L("settings.about"))) {
                    HStack {
                        Text(L("settings.version"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text(L("settings.ai"))) {
                    Toggle(L("settings.ai_enabled"), isOn: $aiEnabled)
                    Text(L("settings.ai_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text(L("settings.glossary"))) {
                    NavigationLink {
                        GlossaryListView()
                    } label: {
                        HStack {
                            Text(L("settings.glossary"))
                            Spacer()
                            Text(String(format: L("glossary.count"), GlossaryManager.shared.terms.count))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text(L("settings.clear_data"))
                    }
                }
            }
            .navigationTitle(L("settings.title"))
            .confirmationDialog(L("settings.clear_confirm"),
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button(L("settings.confirm"), role: .destructive) {
                    deckVM.clearAll()
                }
                Button(L("settings.cancel"), role: .cancel) {}
            }
        }
    }
}
