import Foundation
import Combine

class UsageService: ObservableObject {
    @Published var stats: UsageStats?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var subscriptionType: String?
    @Published var tokenExpiresAt: Date?
    @Published var historyPoints: [Double] = []

    @Published var pinned: PinnedWindow {
        didSet { UserDefaults.standard.set(pinned.rawValue, forKey: Self.pinnedKey) }
    }

    @Published var refreshMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshMinutes, forKey: Self.refreshKey)
            restartTimer()
        }
    }

    @Published var alertThreshold: Int {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: Self.alertKey) }
    }

    private static let pinnedKey  = "pinnedWindow"
    private static let refreshKey = "refreshIntervalMinutes"
    private static let alertKey   = "alertThreshold"
    private static let usageURL   = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"

    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var alertedWindows: Set<String> = []

    init() {
        let storedPin = UserDefaults.standard.string(forKey: Self.pinnedKey)
        self.pinned = storedPin.flatMap(PinnedWindow.init) ?? .highest

        let storedRefresh = UserDefaults.standard.integer(forKey: Self.refreshKey)
        self.refreshMinutes = storedRefresh > 0 ? storedRefresh : 5

        self.alertThreshold = UserDefaults.standard.integer(forKey: Self.alertKey)

        self.historyPoints = UsageHistoryStore.shared.points.map { $0.hourPct }

        log("🔧 UsageService init — refresh=\(refreshMinutes)m alert=\(alertThreshold)%")
        fetchUsage()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Double(refreshMinutes * 60),
            repeats: true
        ) { [weak self] _ in
            self?.log("⏰ Timer fired — refreshing")
            self?.fetchUsage()
        }
    }

    func restartTimer() {
        scheduleTimer()
    }

    func fetchUsage() {
        isLoading = true

        switch KeychainAuth.loadCredentials() {
        case .failure(let err):
            log("🔑 keychain error: \(err)")
            isLoading = false
            errorMessage = err.errorDescription
            return

        case .success(let creds):
            subscriptionType = creds.subscriptionType
            tokenExpiresAt = creds.expiresAt

            if let exp = creds.expiresAt, exp < Date() {
                log("⚠️ token expired at \(exp)")
                isLoading = false
                errorMessage = "Token stale — open Claude Code to refresh"
                return
            }

            performFetch(token: creds.accessToken)
        }
    }

    private func performFetch(token: String) {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        log("🌐 GET \(Self.usageURL.absoluteString)")

        task?.cancel()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                self.handleResponse(data: data, response: response, error: error)
            }
        }
        task?.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            log("❌ network error: \(error.localizedDescription)")
            errorMessage = "Offline — retrying"
            return
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                log("🚫 \(http.statusCode) unauthorized")
                errorMessage = "Token stale — open Claude Code to refresh"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                log("❌ HTTP \(http.statusCode)")
                errorMessage = "API error (HTTP \(http.statusCode))"
                return
            }
        }

        guard let data = data else {
            errorMessage = "Empty response"
            return
        }

        do {
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let newStats = UsageStats(from: decoded, lastUpdated: Date())
            stats = newStats
            errorMessage = nil

            if newStats.hour.available {
                UsageHistoryStore.shared.append(hourPct: newStats.hour.pct)
                historyPoints = UsageHistoryStore.shared.points.map { $0.hourPct }
            }

            AlertService.check(stats: newStats, threshold: alertThreshold, alerted: &alertedWindows)

            log("✅ updated: 5h=\(Int(newStats.hour.pct))% 7d=\(Int(newStats.week.pct))%")
        } catch {
            log("❌ decode error: \(error)")
            errorMessage = "Could not parse usage data"
        }
    }

    // MARK: - Logging (tokens never logged)

    private func log(_ message: String) {
        let logFile = "/tmp/claude-usage-widget.log"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }
}
