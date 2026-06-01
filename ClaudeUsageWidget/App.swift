import SwiftUI

@main
struct ClaudeUsageWidgetApp: App {
    @StateObject private var service: UsageService
    @StateObject private var desktop: DesktopWidgetController

    init() {
        let svc = UsageService()
        _service = StateObject(wrappedValue: svc)
        _desktop = StateObject(wrappedValue: DesktopWidgetController(service: svc))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(service: service, desktop: desktop)
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var service: UsageService

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.medium")
            if let error = service.errorMessage, service.stats == nil {
                Text("⚠️").font(.system(size: 12))
                    .help(error)
            } else if service.stats == nil && service.isLoading {
                Text("…").font(.system(size: 12))
            } else if let value = displayValue {
                Text("\(Int(value))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(UsageColor.forPercentage(value))
            } else {
                Text("—").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    /// The % shown in the menu bar, based on the pinned window.
    private var displayValue: Double? {
        guard let stats = service.stats else { return nil }
        switch service.pinned {
        case .hour:    return stats.hour.available ? stats.hour.pct : nil
        case .week:    return stats.week.available ? stats.week.pct : nil
        case .sonnet:  return stats.sonnetWeek.available ? stats.sonnetWeek.pct : nil
        case .highest:
            let available = [stats.hour, stats.week, stats.sonnetWeek].filter { $0.available }
            return available.map { $0.pct }.max()
        }
    }
}

// MARK: - Shared color logic

enum UsageColor {
    // Vivid, high-contrast palette (reads on any background).
    static let vividGreen  = Color(red: 0.30, green: 0.85, blue: 0.39)
    static let vividAmber  = Color(red: 1.00, green: 0.80, blue: 0.00)
    static let vividOrange = Color(red: 1.00, green: 0.55, blue: 0.10)
    static let vividRed    = Color(red: 1.00, green: 0.27, blue: 0.23)

    static func forPercentage(_ p: Double) -> Color {
        if p >= 90 { return vividRed }
        else if p >= 70 { return vividOrange }
        else if p >= 50 { return vividAmber }
        else { return vividGreen }
    }
}
