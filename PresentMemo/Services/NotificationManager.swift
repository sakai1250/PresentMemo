import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func schedule(for deck: Deck) {
        cancel(for: deck.id)
        guard deck.notificationIntervalHours > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.title", comment: "")
        content.body  = String(format: NSLocalizedString("notification.body", comment: ""), deck.name)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(deck.notificationIntervalHours * 3600),
            repeats: true
        )
        let req = UNNotificationRequest(identifier: deck.id.uuidString,
                                        content: content,
                                        trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancel(for id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
