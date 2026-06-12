import SwiftUI
import AppKit

/// Owns a borderless, always-on-top, draggable NSPanel that floats on the
/// desktop showing the three usage bars. Reuses the live UsageService so the
/// panel updates in lock-step with the menu bar. No Xcode/WidgetKit required.
final class DesktopWidgetController: ObservableObject {
    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private let service: UsageService

    private static let visibleKey = "desktopWidgetVisible"
    private static let frameKey = "desktopWidgetFrameOrigin"

    init(service: UsageService) {
        self.service = service
        if UserDefaults.standard.bool(forKey: Self.visibleKey) {
            // Defer until the run loop is up so screen geometry is ready.
            DispatchQueue.main.async { [weak self] in self?.show() }
        }
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { panel = makePanel() }
        panel?.orderFrontRegardless()
        isVisible = true
        UserDefaults.standard.set(true, forKey: Self.visibleKey)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        UserDefaults.standard.set(false, forKey: Self.visibleKey)
    }

    private func makePanel() -> NSPanel {
        let content = DesktopWidgetView(service: service)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating                 // always on top, glanceable
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true // drag anywhere
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        // Restore saved origin, else top-right corner.
        if let origin = savedOrigin() {
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 240, y: f.maxY - 170))
        }

        // Persist position when the user drags it.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let origin = panel?.frame.origin else { return }
            UserDefaults.standard.set(
                NSStringFromPoint(origin), forKey: Self.frameKey)
        }

        return panel
    }

    private func savedOrigin() -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: Self.frameKey) else { return nil }
        let p = NSPointFromString(s)
        return (p == .zero) ? nil : p
    }
}

// MARK: - Panel content

struct DesktopWidgetView: View {
    @ObservedObject var service: UsageService

    private let panelBG = Color(red: 0.11, green: 0.11, blue: 0.12)  // #1c1c1e

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                ClaudeLogo(size: 14)
                Text("Claude Usage")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }

            if let error = service.errorMessage, service.stats == nil {
                Text(error)
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let stats = service.stats {
                CompactBar(title: "5h", stat: stats.hour)
                CompactBar(title: "Week", stat: stats.week)
                CompactBar(title: "Sonnet", stat: stats.sonnetWeek)
            } else {
                Text("Loading…").font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(15)
        .frame(width: 230, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(panelBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

struct CompactBar: View {
    let title: String
    let stat: WindowStat

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(stat.available ? .white : .white.opacity(0.45))
                .frame(width: 46, alignment: .leading)
            UsageTrack(
                stat: stat,
                trackColor: Color(red: 0.173, green: 0.173, blue: 0.180)
            )
            .frame(height: 6)
            Text(stat.available ? "\(Int(stat.pct))%" : "—")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(stat.available
                    ? UsageColor.forPercentage(stat.pct)
                    : .white.opacity(0.45))
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// Progress track with gradient fill and glow.
struct UsageTrack: View {
    let stat: WindowStat
    let trackColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(trackColor)
                if stat.available && stat.pct > 0 {
                    let colors = UsageColor.gradientColors(for: stat.pct)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [colors.start, colors.end],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .shadow(color: colors.glow, radius: 3, x: 0, y: 0)
                        .frame(width: max(6, geo.size.width * CGFloat(min(stat.pct, 100) / 100)))
                }
            }
        }
    }
}
