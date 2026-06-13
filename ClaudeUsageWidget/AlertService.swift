import Foundation
import UserNotifications

enum AlertService {
    /// Check each alert against its window. `alerted` tracks fired alerts keyed
    /// by "window-threshold"; an entry is cleared when its window drops 5% below
    /// the alert's threshold (re-arm).
    static func check(stats: UsageStats, alerts: [UsageAlert], alerted: inout Set<String>) {
        for alert in alerts {
            let stat = alert.window == .hour ? stats.hour : stats.week
            guard stat.available else { continue }

            let key = "\(alert.window.rawValue)-\(alert.threshold)"
            if stat.pct >= Double(alert.threshold) {
                if !alerted.contains(key) {
                    alerted.insert(key)
                    fire(label: alert.window.notifLabel,
                         pct: stat.pct,
                         resetTime: stat.resetTime,
                         identifier: "usage-alert-\(key)")
                }
            } else if stat.pct < Double(alert.threshold) - 5.0 {
                alerted.remove(key)
            }
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
