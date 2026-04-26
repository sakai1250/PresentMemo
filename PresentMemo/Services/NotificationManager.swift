import Foundation
import UserNotifications

struct ReminderRule: Identifiable, Codable, Equatable {
    let id: UUID
    var weekday: Int   // 1 = Sunday ... 7 = Saturday
    var hour: Int
    var minute: Int
    var comment: String

    init(id: UUID = UUID(), weekday: Int, hour: Int, minute: Int, comment: String = "") {
        self.id = id
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.comment = comment
    }
}

class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let rulesKey = "pm.reminder.rules.v1"
    private let requestPrefix = "pm.reminder.rule."

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func loadRules() -> [ReminderRule] {
        guard let data = UserDefaults.standard.data(forKey: rulesKey),
              let decoded = try? JSONDecoder().decode([ReminderRule].self, from: data) else {
            return defaultRules()
        }
        if decoded.isEmpty {
            return defaultRules()
        }
        return decoded
    }

    func saveRules(_ rules: [ReminderRule], decks: [Deck]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
        scheduleAll(for: decks, rules: rules)
    }

    func scheduleAll(for decks: [Deck]) {
        let rules = loadRules()
        scheduleAll(for: decks, rules: rules)
    }

    func schedule(for deck: Deck) {
        // Compatibility entrypoint
        scheduleAll(for: [deck])
    }

    func cancel(for id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func scheduleAll(for decks: [Deck], rules: [ReminderRule]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [requestPrefix] requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(requestPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)

            guard !rules.isEmpty else { return }

            for rule in rules {
                let content = self.makeContent(decks: decks, rule: rule)

                var date = DateComponents()
                date.weekday = min(max(rule.weekday, 1), 7)
                date.hour = min(max(rule.hour, 0), 23)
                date.minute = min(max(rule.minute, 0), 59)

                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                let request = UNNotificationRequest(
                    identifier: self.requestPrefix + rule.id.uuidString,
                    content: content,
                    trigger: trigger
                )
                center.add(request, withCompletionHandler: nil)
            }
        }
    }

    private func makeContent(decks: [Deck], rule: ReminderRule) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.title", comment: "")

        if let target = weakestCard(from: decks) {
            content.body = String(
                format: NSLocalizedString("notification.word_body", comment: ""),
                target.card.term,
                target.deckName
            )
            let subtitleComment = rule.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !subtitleComment.isEmpty {
                content.subtitle = subtitleComment
            } else if !target.card.definition.isEmpty {
                content.subtitle = String(target.card.definition.prefix(50))
            }
        } else {
            content.body = NSLocalizedString("notification.fallback_body", comment: "")
            let subtitleComment = rule.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !subtitleComment.isEmpty {
                content.subtitle = subtitleComment
            }
        }

        content.sound = .default
        return content
    }

    private func weakestCard(from decks: [Deck]) -> (deckName: String, card: Flashcard)? {
        decks
            .flatMap { deck in
                deck.cards.map { (deckName: deck.name, card: $0) }
            }
            .filter { !$0.card.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.card.mastery != $1.card.mastery {
                    return $0.card.mastery < $1.card.mastery
                }
                if $0.card.reviewCount != $1.card.reviewCount {
                    return $0.card.reviewCount < $1.card.reviewCount
                }
                return $0.card.term.localizedCaseInsensitiveCompare($1.card.term) == .orderedAscending
            }
            .first
    }

    private func defaultRules() -> [ReminderRule] {
        [ReminderRule(weekday: 2, hour: 21, minute: 0, comment: "")]
    }
}
