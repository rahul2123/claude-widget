import SwiftUI

// MARK: - Root View

struct MenuBarView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var desktop: DesktopWidgetController
    @State private var showingAbout = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(service: service, showingAbout: $showingAbout)
            Divider().padding(.vertical, 8)

            if showingAbout {
                AboutView(service: service)
            } else {
                ContentView(service: service)
                Divider().padding(.vertical, 8)
                PinSelectorView(service: service)
                Divider().padding(.vertical, 8)
                FooterView(service: service, desktop: desktop)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - Header

struct HeaderView: View {
    @ObservedObject var service: UsageService
    @Binding var showingAbout: Bool

    var body: some View {
        HStack {
            Text("Claude Usage").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { service.fetchUsage() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Refresh")
            Button { showingAbout.toggle() } label: {
                Image(systemName: showingAbout ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("About")
        }
    }
}

// MARK: - Content (3 windows or error)

struct ContentView: View {
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
                Text("Loading…").font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

struct ErrorView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 14))
            Text(message).font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - One window row (label, %, bar, reset countdown)

struct WindowRow: View {
    let title: String
    let stat: WindowStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(stat.available ? .primary : .secondary)
                Spacer()
                if stat.available {
                    Text("\(Int(stat.pct))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UsageColor.forPercentage(stat.pct))
                } else {
                    Text("—").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            bar
            if stat.available {
                if let reset = stat.resetTime {
                    Text("resets \(resetText(reset))")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            } else {
                Text("not available")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                if stat.available {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(UsageColor.forPercentage(stat.pct))
                        .frame(width: geo.size.width * CGFloat(min(stat.pct, 100) / 100))
                }
            }
        }
        .frame(height: 6)
    }

    private func resetText(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "now" }
        // Under 24h → countdown; otherwise → calendar date.
        if interval < 86_400 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return fmt.string(from: date)
        }
    }
}

// MARK: - Pin selector

struct PinSelectorView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        HStack(spacing: 4) {
            Text("Menu bar:").font(.system(size: 10)).foregroundColor(.secondary)
            ForEach(PinnedWindow.allCases, id: \.self) { window in
                Button {
                    service.pinned = window
                } label: {
                    Text(window.label)
                        .font(.system(size: 10, weight: service.pinned == window ? .semibold : .regular))
                        .foregroundColor(service.pinned == window ? .white : .secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(service.pinned == window ? Color.accentColor : Color.gray.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var desktop: DesktopWidgetController

    var body: some View {
        HStack(spacing: 12) {
            if let stats = service.stats {
                Text("updated \(timeString(stats.lastUpdated))")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button(desktop.isVisible ? "Hide widget" : "Show widget") {
                desktop.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.accentColor)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - About / status

struct AboutView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Account", service.subscriptionType ?? "—")
            row("Token expires", expiryText)
            Text("Auth is read from the Claude Code keychain. The Claude Code daemon keeps the token fresh.")
                .font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium))
        }
    }

    private var expiryText: String {
        guard let exp = service.tokenExpiresAt else { return "unknown" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm"
        return fmt.string(from: exp)
    }
}
