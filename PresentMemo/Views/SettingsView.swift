import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var deckVM: DeckViewModel
    @State private var showClearConfirm = false
    @EnvironmentObject var coachMark: CoachMarkManager
    @State private var showAddReminder = false
    @State private var reminderRules: [ReminderRule] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("settings.notifications"))) {
                    if reminderRules.isEmpty {
                        Text(L("settings.reminder_empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reminderRules) { rule in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ruleDisplay(rule))
                                    .font(.subheadline.bold())
                                if !rule.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(rule.comment)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: deleteRules)
                    }

                    Button {
                        showAddReminder = true
                    } label: {
                        Label(L("settings.add_reminder"), systemImage: "plus.circle")
                    }
                }

                Section(header: Text(L("settings.about"))) {
                    HStack {
                        Text(L("settings.version"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    Button(L("settings.open_tutorial")) {
                        coachMark.restart()
                    }
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
            .onAppear {
                reminderRules = NotificationManager.shared.loadRules()
            }
            .confirmationDialog(
                L("settings.clear_confirm"),
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button(L("settings.confirm"), role: .destructive) {
                    deckVM.clearAll()
                }
                Button(L("settings.cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showAddReminder) {
                ReminderRuleEditorSheet { weekday, hour, minute, comment in
                    NotificationManager.shared.requestPermission()
                    reminderRules.append(ReminderRule(weekday: weekday, hour: hour, minute: minute, comment: comment))
                    NotificationManager.shared.saveRules(reminderRules, decks: deckVM.decks)
                }
            }
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        reminderRules.remove(atOffsets: offsets)
        NotificationManager.shared.saveRules(reminderRules, decks: deckVM.decks)
    }

    private func ruleDisplay(_ rule: ReminderRule) -> String {
        let weekdaySymbols = Calendar.current.weekdaySymbols
        let index = min(max(rule.weekday - 1, 0), weekdaySymbols.count - 1)
        let weekday = weekdaySymbols[index]
        let time = String(format: "%02d:%02d", rule.hour, rule.minute)
        return "\(weekday)  \(time)"
    }
}

private struct ReminderRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var weekday: Int = Calendar.current.component(.weekday, from: Date())
    @State private var time = Date()
    @State private var comment = ""

    let onSave: (_ weekday: Int, _ hour: Int, _ minute: Int, _ comment: String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("settings.reminder_weekday"))) {
                    Picker(L("settings.reminder_weekday"), selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                }

                Section(header: Text(L("settings.reminder_time"))) {
                    DatePicker(
                        L("settings.reminder_time"),
                        selection: $time,
                        displayedComponents: .hourAndMinute
                    )
                }

                Section(header: Text(L("settings.reminder_comment"))) {
                    TextField(L("settings.reminder_comment_placeholder"), text: $comment)
                }
            }
            .navigationTitle(L("settings.add_reminder"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("button.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("button.save")) {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onSave(
                            weekday,
                            components.hour ?? 21,
                            components.minute ?? 0,
                            comment.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
