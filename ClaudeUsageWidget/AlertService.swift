import Foundation
import UserNotifications

enum AlertService {
    /// Check all windows against threshold. `alerted` tracks which windows have
    /// already fired a notification; cleared when the window drops 5% below threshold.
    static func check(stats: UsageStats, threshold: Int, alerted: inout Set<String>) {
        guard threshold > 0 else { return }

        let windows: [(key: String, label: String, stat: WindowStat)] = [
            ("hour",   "5-hour",        stats.hour),
            ("week",   "Weekly",        stats.week),
            ("sonnet", "Sonnet (week)", stats.sonnetWeek),
        ]

        for (key, label, stat) in windows {
            guard stat.available else { continue }
            if stat.pct >= Double(threshold) {
                if !alerted.contains(key) {
                    alerted.insert(key)
                    fire(label: label, pct: stat.pct, resetTime: stat.resetTime)
                }
            } else if stat.pct < Double(threshold) - 5.0 {
                alerted.remove(key)
            }
        }
    }

    private static func fire(label: String, pct: Double, resetTime: Date?) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Claude Usage"
            content.body = "\(label) at \(Int(pct))%\(resetSuffix(resetTime))"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "usage-alert-\(label)-\(Int(pct))",
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
