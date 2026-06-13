import Foundation

// MARK: - Raw API Response
// GET https://api.anthropic.com/api/oauth/usage
// Each window: { utilization: 0-100 float, resets_at: ISO8601 } or null.

struct UsageResponse: Codable {
    let five_hour: Window?
    let seven_day: Window?
    let seven_day_sonnet: Window?
    let seven_day_opus: Window?

    struct Window: Codable {
        let utilization: Double
        let resets_at: String?
    }
}

// MARK: - Display Model

struct WindowStat {
    let pct: Double
    let resetTime: Date?
    let available: Bool

    static let unavailable = WindowStat(pct: 0, resetTime: nil, available: false)

    init(pct: Double, resetTime: Date?, available: Bool) {
        self.pct = pct
        self.resetTime = resetTime
        self.available = available
    }

    /// Build from a raw API window. nil window → unavailable.
    init(from window: UsageResponse.Window?) {
        guard let window = window else {
            self = .unavailable
            return
        }
        self.pct = window.utilization
        self.resetTime = window.resets_at.flatMap { WindowStat.parseDate($0) }
        self.available = true
    }

    // API emits microsecond precision (e.g. "2026-06-01T18:59:59.776995+00:00").
    // ISO8601DateFormatter only reliably handles milliseconds, so try with
    // fractional seconds first, then fall back to whole seconds.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = isoFractional.date(from: s) { return d }
        // Strip any fractional component, then parse whole seconds.
        let stripped = s.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return isoWhole.date(from: stripped)
    }
}

struct UsageStats {
    let hour: WindowStat        // five_hour
    let week: WindowStat        // seven_day
    let sonnetWeek: WindowStat  // seven_day_sonnet
    let lastUpdated: Date

    init(from response: UsageResponse, lastUpdated: Date) {
        self.hour = WindowStat(from: response.five_hour)
        self.week = WindowStat(from: response.seven_day)
        self.sonnetWeek = WindowStat(from: response.seven_day_sonnet)
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Pinned Window (menu bar label selection)

enum PinnedWindow: String, CaseIterable {
    case highest, hour, week, sonnet, bothHourWeek

    var label: String {
        switch self {
        case .highest:      return "highest"
        case .hour:         return "5h"
        case .week:         return "week"
        case .sonnet:       return "sonnet"
        case .bothHourWeek: return "5h+Wk"
        }
    }
}

// MARK: - Usage Alerts

enum AlertWindow: String, Codable, CaseIterable {
    case hour, week

    /// Short label for the segmented toggle.
    var label: String { self == .hour ? "5h" : "Wk" }
    /// Human label used in the notification body.
    var notifLabel: String { self == .hour ? "5-hour" : "Weekly" }
}

struct UsageAlert: Codable, Identifiable, Equatable {
    var id = UUID()
    var window: AlertWindow
    var threshold: Int   // 5...100, multiples of 5
}
