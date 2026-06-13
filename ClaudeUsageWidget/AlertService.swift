import Foundation
import UserNotifications

enum AlertService {
    /// Check each alert against its window. `alerted` tracks fired alerts keyed
    /// by "window-threshold"; an entry is cleared when its window drops 5% below
    /// the alert's threshold (re-arm).
    static func check(stats: UsageStats, alerts: [UsageAlert], alerted: inout Set<String>) {
        let result = AlertValidation.evaluate(stats: stats, alerts: alerts, alerted: alerted)
        result.toArm.forEach { alerted.insert($0) }
        result.toDisarm.forEach { alerted.remove($0) }
        for item in result.toFire {
            fire(label: item.alert.window.notifLabel,
                 pct: item.pct,
                 resetTime: item.resetTime,
                 identifier: "usage-alert-\(item.alert.window.rawValue)-\(item.alert.threshold)")
        }
    }

    private static func fire(label: String, pct: Double, resetTime: Date?, identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Claude Usage"
            content.body = "\(label) at \(Int(pct))%\(resetSuffix(resetTime))"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    private static func resetSuffix(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "" }
        if interval < 86_400 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            return h > 0 ? " — resets in \(h)h \(m)m" : " — resets in \(m)m"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return " — resets \(fmt.string(from: date))"
    }
}
