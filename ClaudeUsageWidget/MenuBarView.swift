import SwiftUI

// MARK: - Root

struct MenuBarView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var desktop: DesktopWidgetController
    @State private var showingSettings = false

    private let sep = Color(red: 0.173, green: 0.173, blue: 0.180)

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(service: service, showingSettings: $showingSettings)
            sep.frame(height: 1).padding(.vertical, 8)

            if showingSettings {
                SettingsView(service: service, desktop: desktop)
                sep.frame(height: 1).padding(.vertical, 8)
                SettingsFooterView()
            } else {
                UsageContentView(service: service)
                sep.frame(height: 1).padding(.vertical, 8)
                SparklineView(points: service.historyPoints)
                sep.frame(height: 1).padding(.vertical, 8)
                FooterView(service: service, desktop: desktop)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Header

struct HeaderView: View {
    @ObservedObject var service: UsageService
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 6) {
            ClaudeLogo(size: 15)
            Text("Claude Usage").font(.system(size: 13, weight: .semibold))
            Spacer()
            if showingSettings {
                Button {
                    showingSettings = false
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 11))
                        Text("Back").font(.system(size: 11))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Button { service.fetchUsage() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Refresh")
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
    }
}

// MARK: - Usage content (3 rows or error/loading)

struct UsageContentView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        if let error = service.errorMessage, service.stats == nil {
            ErrorView(message: error)
        } else if let stats = service.stats {
            VStack(spacing: 12) {
                WindowRow(title: "5-hour", stat: stats.hour)
                WindowRow(title: "Week", stat: stats.week)
                WindowRow(title: "Sonnet (week)", stat: stats.sonnetWeek)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("Loading…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Error

struct ErrorView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 14))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Window row

struct WindowRow: View {
    let title: String
    let stat: WindowStat

    private let labelColor  = Color(red: 0.682, green: 0.682, blue: 0.698)  // #aeaeb2
    private let secondColor = Color(red: 0.282, green: 0.282, blue: 0.290)  // #48484a
    private let trackColor  = Color(red: 0.173, green: 0.173, blue: 0.180)  // #2c2c2e

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(stat.available ? labelColor : labelColor.opacity(0.5))
                Spacer()
                if stat.available {
                    Text("\(Int(stat.pct))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UsageColor.forPercentage(stat.pct))
                } else {
                    Text("—").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            UsageTrack(stat: stat, trackColor: trackColor).frame(height: 6)
            if stat.available, let reset = stat.resetTime {
                Text("resets \(resetText(reset))")
                    .font(.system(size: 9))
                    .foregroundColor(secondColor)
            } else if !stat.available {
                Text("not available")
                    .font(.system(size: 9))
                    .foregroundColor(secondColor)
            }
        }
    }

    private func resetText(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "now" }
        if interval < 86_400 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    let points: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("5-hour · today")
                .font(.system(size: 9))
                .foregroundColor(Color(red: 0.388, green: 0.388, blue: 0.400))
            Canvas { context, size in
                guard points.count >= 2 else { return }
                let minVal = points.min() ?? 0
                let maxVal = max((points.max() ?? 100), minVal + 1)
                var path = Path()
                for (i, p) in points.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(points.count - 1)
                    let normalized = CGFloat((p - minVal) / (maxVal - minVal))
                    let y = size.height * (1.0 - normalized)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else       { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(
                    path,
                    with: .color(Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.8)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.173, green: 0.173, blue: 0.180))
        )
    }
}

// MARK: - Footer (main view)

struct FooterView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var desktop: DesktopWidgetController

    var body: some View {
        HStack {
            if let stats = service.stats {
                Text("↺ every \(service.refreshMinutes)m · \(timeString(stats.lastUpdated))")
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 0.282, green: 0.282, blue: 0.290))
            }
            Spacer()
            Button(desktop.isVisible ? "Hide widget" : "Show widget") {
                desktop.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(.accentColor)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.392, green: 0.392, blue: 0.400))
        }
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var desktop: DesktopWidgetController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Menu bar label") {
                HStack(spacing: 4) {
                    ForEach(PinnedWindow.allCases, id: \.self) { window in
                        pillButton(window.label, selected: service.pinned == window) {
                            service.pinned = window
                        }
                    }
                }
            }
            settingsSection("Refresh every") {
                HStack(spacing: 4) {
                    ForEach([1, 2, 3, 4, 5], id: \.self) { min in
                        pillButton("\(min)m", selected: service.refreshMinutes == min) {
                            service.refreshMinutes = min
                        }
                    }
                }
            }
            settingsSection("Alert when usage exceeds") {
                HStack(spacing: 4) {
                    pillButton("Off", selected: service.alertThreshold == 0) {
                        service.alertThreshold = 0
                    }
                    ForEach([70, 80, 90], id: \.self) { threshold in
                        pillButton("\(threshold)%", selected: service.alertThreshold == threshold) {
                            service.alertThreshold = threshold
                        }
                    }
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desktop widget")
                        .font(.system(size: 11))
                    Text("Floating always-on-top panel")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.388, green: 0.388, blue: 0.400))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { desktop.isVisible },
                    set: { newVal in if newVal != desktop.isVisible { desktop.toggle() } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9))
                .foregroundColor(Color(red: 0.388, green: 0.388, blue: 0.400))
                .tracking(0.6)
            content()
        }
    }

    private func pillButton(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundColor(selected
                    ? .white
                    : Color(red: 0.557, green: 0.557, blue: 0.576))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected
                            ? Color(red: 0.039, green: 0.518, blue: 1.000)
                            : Color(red: 0.173, green: 0.173, blue: 0.180))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings footer

struct SettingsFooterView: View {
    var body: some View {
        HStack {
            Text("com.claudeusagewidget.app")
                .font(.system(size: 9))
                .foregroundColor(Color(red: 0.282, green: 0.282, blue: 0.290))
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.392, green: 0.392, blue: 0.400))
        }
    }
}
