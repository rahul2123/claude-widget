import Foundation

enum AlertValidation {
    /// Whether the stepper can decrement without violating ordering constraints.
    /// - threshold must stay > 5 (absolute minimum)
    /// - threshold - 5 must stay strictly above prevThreshold
    static func canDecrement(threshold: Int, prevThreshold: Int?) -> Bool {
        guard threshold > 5 else { return false }
        if let prev = prevThreshold { return threshold - 5 > prev }
        return true
    }

    /// Whether the stepper can increment without violating ordering constraints.
    /// - threshold must stay < 100 (absolute maximum)
    /// - threshold + 5 must stay strictly below nextThreshold
    static func canIncrement(threshold: Int, nextThreshold: Int?) -> Bool {
        guard threshold < 100 else { return false }
        if let next = nextThreshold { return threshold + 5 < next }
        return true
    }

    /// Default threshold when adding a new alert to a tab.
    /// Places the new alert 5 above the current highest, or 80 if the tab is empty.
    static func defaultThreshold(forTab tab: AlertWindow, existing alerts: [UsageAlert]) -> Int {
        let sorted = alerts
            .filter { $0.window == tab }
            .sorted { $0.threshold < $1.threshold }
        return sorted.last.map { min(100, $0.threshold + 5) } ?? 80
    }

    /// Sorted (ascending) indices into `alerts` for a given window tab.
    /// Returns (originalIndex, alert) pairs sorted by threshold.
    static func sortedTabPairs(
        in alerts: [UsageAlert],
        tab: AlertWindow
    ) -> [(offset: Int, element: UsageAlert)] {
        alerts
            .enumerated()
            .filter { $0.element.window == tab }
            .sorted { $0.element.threshold < $1.element.threshold }
    }

    // MARK: - Pure check logic (no side effects; used by AlertService and tests)

    struct CheckResult {
        /// Alerts that should fire a notification (not yet in alerted set).
        var toFire: [(alert: UsageAlert, pct: Double, resetTime: Date?)] = []
        /// Keys to insert into the alerted set.
        var toArm: [String] = []
        /// Keys to remove from the alerted set (re-arm).
        var toDisarm: [String] = []
    }

    /// Pure decision function: given current stats, alerts, and the armed-key set,
    /// returns what should fire, what should arm, and what should disarm.
    /// Does NOT mutate `alerted` or send notifications.
    static func evaluate(
        stats: UsageStats,
        alerts: [UsageAlert],
        alerted: Set<String>
    ) -> CheckResult {
        var result = CheckResult()
        for alert in alerts {
            let stat = alert.window == .hour ? stats.hour : stats.week
            guard stat.available else { continue }
            let key = "\(alert.window.rawValue)-\(alert.threshold)"
            if stat.pct >= Double(alert.threshold) {
                if !alerted.contains(key) {
                    result.toArm.append(key)
                    result.toFire.append((alert: alert, pct: stat.pct, resetTime: stat.resetTime))
                }
            } else if stat.pct < Double(alert.threshold) - 5.0 {
                if alerted.contains(key) {
                    result.toDisarm.append(key)
                }
            }
        }
        return result
    }
}
