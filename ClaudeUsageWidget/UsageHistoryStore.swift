import Foundation

struct HistoryPoint: Codable {
    let timestamp: Date
    let hourPct: Double
}

final class UsageHistoryStore {
    static let shared = UsageHistoryStore()
    private static let key = "usageHistoryPoints"
    private static let maxPoints = 100  // ~8h at 5-min default

    private(set) var points: [HistoryPoint] = []

    private init() { load() }

    func append(hourPct: Double) {
        points.append(HistoryPoint(timestamp: Date(), hourPct: hourPct))
        if points.count > Self.maxPoints {
            points.removeFirst(points.count - Self.maxPoints)
        }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([HistoryPoint].self, from: data)
        else { return }
        points = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
