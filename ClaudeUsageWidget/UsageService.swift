import Foundation
import Combine

/// Fetches Claude usage from the Anthropic OAuth usage endpoint and publishes
/// a display-ready `UsageStats`. Read-only auth: the token comes from the
/// Keychain (kept fresh by Claude Code's daemon).
class UsageService: ObservableObject {
    @Published var stats: UsageStats?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var subscriptionType: String?
    @Published var tokenExpiresAt: Date?

    /// Persisted in UserDefaults; controls which window the menu bar label shows.
    @Published var pinned: PinnedWindow {
        didSet { UserDefaults.standard.set(pinned.rawValue, forKey: Self.pinnedKey) }
    }

    private static let pinnedKey = "pinnedWindow"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"

    private var timer: Timer?
    private var task: URLSessionDataTask?

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.pinnedKey)
        self.pinned = stored.flatMap(PinnedWindow.init) ?? .highest
        log("🔧 UsageService init")
        startFetching()
    }

    private func startFetching() {
        fetchUsage()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.log("⏰ Timer fired — refreshing")
            self?.fetchUsage()
        }
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

            // If the token is already expired, the daemon hasn't refreshed yet.
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
            stats = UsageStats(from: decoded, lastUpdated: Date())
            errorMessage = nil
            log("✅ updated: 5h=\(Int(stats?.hour.pct ?? -1))% 7d=\(Int(stats?.week.pct ?? -1))%")
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
