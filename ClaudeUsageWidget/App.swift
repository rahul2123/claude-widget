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
            ClaudeLogo(size: 14)
            if let error = service.errorMessage, service.stats == nil {
                Text("⚠️").font(.system(size: 12)).help(error)
            } else if service.stats == nil && service.isLoading {
                Text("…").font(.system(size: 12))
            } else if service.pinned == .bothHourWeek, let stats = service.stats {
                bothLabel(stats: stats)
            } else if let value = displayValue {
                Text("\(Int(value))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(UsageColor.forPercentage(value))
            } else {
                Text("—").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func bothLabel(stats: UsageStats) -> some View {
        let hourOK = stats.hour.available
        let weekOK = stats.week.available
        if hourOK && weekOK {
            HStack(spacing: 2) {
                Text("\(Int(stats.hour.pct))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(UsageColor.forPercentage(stats.hour.pct))
                Text("/")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.39, green: 0.39, blue: 0.40))
                Text("\(Int(stats.week.pct))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(UsageColor.forPercentage(stats.week.pct))
            }
        } else if hourOK {
            Text("\(Int(stats.hour.pct))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(UsageColor.forPercentage(stats.hour.pct))
        } else if weekOK {
            Text("\(Int(stats.week.pct))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(UsageColor.forPercentage(stats.week.pct))
        } else {
            Text("—").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private var displayValue: Double? {
        guard let stats = service.stats else { return nil }
        switch service.pinned {
        case .hour:         return stats.hour.available ? stats.hour.pct : nil
        case .week:         return stats.week.available ? stats.week.pct : nil
        case .sonnet:       return stats.sonnetWeek.available ? stats.sonnetWeek.pct : nil
        case .bothHourWeek: return nil
        case .highest:
            let available = [stats.hour, stats.week, stats.sonnetWeek].filter { $0.available }
            return available.map { $0.pct }.max()
        }
    }
}

// MARK: - Shared color logic

// MARK: - Claude logo (official PNG with a vector fallback)

struct ClaudeLogo: View {
    var size: CGFloat
    var color: Color = Color(red: 0.85, green: 0.47, blue: 0.36)  // Claude coral #D9785C

    private static let base: NSImage? = {
        guard let url = Bundle.main.url(forResource: "claude-logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Returns a copy sized to `pt` points. The menu bar renders an NSImage at
    /// its `.size`, ignoring SwiftUI `.frame()`, so we set the size explicitly.
    private static func sized(_ pt: CGFloat) -> NSImage? {
        guard let base = base, let copy = base.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: pt, height: pt)
        copy.isTemplate = false
        return copy
    }

    var body: some View {
        if let img = Self.sized(size) {
            Image(nsImage: img)
                .renderingMode(.original)
                .interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            VectorMark(size: size, color: color)
        }
    }
}

// Drawn fallback used only if the bundled PNG is missing.
struct VectorMark: View {
    var size: CGFloat
    var color: Color

    private let rays: [CGFloat] = [
        1.00, 0.62, 0.90, 0.55, 1.00, 0.62,
        0.90, 0.55, 1.00, 0.62, 0.90, 0.55,
    ]

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = min(sz.width, sz.height) / 2
            let inner = r * 0.16
            let lineW = max(1, r * 0.18)
            let count = rays.count
            for i in 0..<count {
                let angle = (2 * CGFloat.pi / CGFloat(count)) * CGFloat(i) - .pi / 2
                let outer = r * rays[i]
                var path = Path()
                path.move(to: CGPoint(x: c.x + cos(angle) * inner,
                                      y: c.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: c.x + cos(angle) * outer,
                                         y: c.y + sin(angle) * outer))
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: lineW, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

enum UsageColor {
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

    /// Gradient start, end, and glow for the usage track fill.
    static func gradientColors(for p: Double) -> (start: Color, end: Color, glow: Color) {
        if p >= 90 {
            return (Color(red: 0.478, green: 0.102, blue: 0.086),
                    Color(red: 1.000, green: 0.271, blue: 0.227),
                    Color(red: 1.000, green: 0.271, blue: 0.227).opacity(0.33))
        } else if p >= 70 {
            return (Color(red: 0.478, green: 0.188, blue: 0.000),
                    Color(red: 1.000, green: 0.420, blue: 0.000),
                    Color(red: 1.000, green: 0.420, blue: 0.000).opacity(0.33))
        } else if p >= 50 {
            return (Color(red: 0.478, green: 0.290, blue: 0.000),
                    Color(red: 1.000, green: 0.624, blue: 0.039),
                    Color(red: 1.000, green: 0.624, blue: 0.039).opacity(0.33))
        } else {
            return (Color(red: 0.102, green: 0.478, blue: 0.208),
                    Color(red: 0.204, green: 0.780, blue: 0.349),
                    Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.40))
        }
    }
}
