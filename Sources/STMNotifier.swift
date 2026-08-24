import Foundation
import UserNotifications

enum STMNotifier {
    static func configure(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Logger.log("notification authorization failed \(error.localizedDescription)")
            } else {
                Logger.log("notification authorization granted=\(granted)")
            }
        }
    }

    static func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "stm-desktop-listener-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.log("notification delivery failed \(error.localizedDescription)")
            }
        }
    }
}
