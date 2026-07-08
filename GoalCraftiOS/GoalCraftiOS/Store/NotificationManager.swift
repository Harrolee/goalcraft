import Foundation
import UserNotifications

/// Bowie-voiced re-engagement nudges — emotionally resonant like Duo's, but
/// intimate and theatrical, as if he's leaving you a note at the front desk.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var enabled = false

    private let center = UNUserNotificationCenter.current()

    /// The voice: coaxing, tender, a little cosmic. Never scolding — always
    /// certain you're capable of more than you're letting on.
    static let nudges: [(title: String, body: String)] = [
        ("Darling.", "A song came to me in a dream last night. Did you write yours down today?"),
        ("It's me.", "The ledger's gone awfully quiet. That isn't like you, and we both know it."),
        ("One small mark.", "That's all I'm asking tonight, sweet thing. Just the one. I'll wait."),
        ("Somewhere out there…", "a stranger is already in love with a song you haven't finished. Don't keep them."),
        ("You promised me.", "You said this wouldn't be boring. Go on — add one to the count and prove it."),
        ("Come now.", "Heroes aren't made on the easy days. They're made on the ones like today."),
        ("Still humming.", "I've had your melody in my head since morning. Your move, gorgeous."),
        ("Don't wait for the mood.", "The mood arrives after you begin, never before. Make a mark. I'll meet you there."),
    ]

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        enabled = settings.authorizationStatus == .authorized
    }

    /// Ask permission, then schedule the week of nudges. Returns granted.
    @discardableResult
    func enableNudges() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            enabled = granted
            if granted { scheduleWeek() }
            return granted
        } catch {
            enabled = false
            return false
        }
    }

    func disableNudges() {
        center.removeAllPendingNotificationRequests()
        enabled = false
    }

    /// Seven nudges, one per weekday at 8pm, repeating weekly — so the voice
    /// rotates instead of repeating the same line every night.
    private func scheduleWeek() {
        center.removeAllPendingNotificationRequests()
        for (index, nudge) in Self.nudges.prefix(7).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default

            var date = DateComponents()
            date.weekday = index + 1   // 1 = Sunday … 7 = Saturday
            date.hour = 20
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: "bowie.nudge.\(index)",
                                                content: content, trigger: trigger)
            center.add(request)
        }
    }
}
