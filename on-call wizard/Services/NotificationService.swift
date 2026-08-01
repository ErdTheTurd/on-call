import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func notifyTradeRequest(fromDoctor: String, shiftDate: Date) {
        scheduleLocal(
            title: "Trade Request",
            body: "\(fromDoctor) wants to trade a shift on \(shiftDate.formatted(date: .abbreviated, time: .omitted))"
        )
    }

    func notifyTokenDecision(approved: Bool, date: Date) {
        scheduleLocal(
            title: approved ? "Day Approved" : "Day Denied",
            body: "Your request for \(date.formatted(date: .abbreviated, time: .omitted)) was \(approved ? "approved" : "denied")."
        )
    }

    private func scheduleLocal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
