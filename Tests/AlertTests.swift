import Foundation
import UserNotifications

// MARK: - Test harness

private var passed = 0
private var failed = 0
private var currentSection = ""

private func section(_ name: String, _ body: () -> Void) {
    currentSection = name
    print("\n\(name)")
    body()
}

private func expect(_ condition: Bool, _ message: String,
                    file: StaticString = #file, line: UInt = #line) {
    if condition {
        print("  ✓ \(message)")
        passed += 1
    } else {
        print("  ✗ FAIL: \(message)  (line \(line))")
        failed += 1
    }
}

private func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String,
                                       file: StaticString = #file, line: UInt = #line) {
    if a == b {
        print("  ✓ \(message)")
        passed += 1
    } else {
        print("  ✗ FAIL: \(message) — got \(a), expected \(b)  (line \(line))")
        failed += 1
    }
}

// MARK: - Helpers

private func makeStats(hourPct: Double = 0, weekPct: Double = 0,
                       hourAvail: Bool = true, weekAvail: Bool = true) -> UsageStats {
    UsageStats(
        hour: WindowStat(pct: hourPct, resetTime: nil, available: hourAvail),
        week: WindowStat(pct: weekPct, resetTime: nil, available: weekAvail),
        sonnetWeek: WindowStat(pct: 0, resetTime: nil, available: false),
        lastUpdated: Date()
    )
}

private func makeAlert(_ window: AlertWindow, _ threshold: Int) -> UsageAlert {
    UsageAlert(window: window, threshold: threshold)
}

// MARK: - AlertWindow

func testAlertWindow() {
    section("AlertWindow") {
        expectEqual(AlertWindow.hour.label, "5h", "hour.label == 5h")
        expectEqual(AlertWindow.week.label, "Wk", "week.label == Wk")
        expectEqual(AlertWindow.hour.notifLabel, "5-hour", "hour.notifLabel == 5-hour")
        expectEqual(AlertWindow.week.notifLabel, "Weekly", "week.notifLabel == Weekly")
        expectEqual(AlertWindow.hour.rawValue, "hour", "hour.rawValue == hour")
        expectEqual(AlertWindow.week.rawValue, "week", "week.rawValue == week")
        expectEqual(AlertWindow.allCases.count, 2, "exactly 2 cases")
        expect(AlertWindow.allCases.contains(.hour), "allCases contains .hour")
        expect(AlertWindow.allCases.contains(.week), "allCases contains .week")
    }
}

// MARK: - UsageAlert

func testUsageAlert() {
    section("UsageAlert") {
        let a = makeAlert(.hour, 80)
        expectEqual(a.window, .hour, "window stored correctly")
        expectEqual(a.threshold, 80, "threshold stored correctly")

        let b = makeAlert(.hour, 80)
        expect(a.id != b.id, "two alerts have distinct UUIDs")
        expect(a != b, "two alerts with same window/threshold but different id are not equal")

        // Codable round-trip
        let encoded = try! JSONEncoder().encode(a)
        let decoded = try! JSONDecoder().decode(UsageAlert.self, from: encoded)
        expectEqual(decoded.id, a.id, "codable: id survives round-trip")
        expectEqual(decoded.window, a.window, "codable: window survives round-trip")
        expectEqual(decoded.threshold, a.threshold, "codable: threshold survives round-trip")
        expect(decoded == a, "codable: decoded == original")

        // AlertWindow Codable
        let winData = try! JSONEncoder().encode(AlertWindow.week)
        let winDecoded = try! JSONDecoder().decode(AlertWindow.self, from: winData)
        expectEqual(winDecoded, .week, "AlertWindow.week codable round-trip")
    }
}

// MARK: - AlertValidation.canDecrement

func testCanDecrement() {
    section("AlertValidation.canDecrement") {
        // Absolute floor
        expect(!AlertValidation.canDecrement(threshold: 5, prevThreshold: nil),
               "5 — no prev — cannot decrement (already at floor)")
        expect(!AlertValidation.canDecrement(threshold: 5, prevThreshold: 0),
               "5 — prev=0 — cannot decrement (floor)")

        // Free decrements (no prev)
        expect(AlertValidation.canDecrement(threshold: 10, prevThreshold: nil),
               "10 — no prev — can decrement to 5")
        expect(AlertValidation.canDecrement(threshold: 100, prevThreshold: nil),
               "100 — no prev — can decrement")

        // Ordering constraint
        expect(AlertValidation.canDecrement(threshold: 15, prevThreshold: 5),
               "15 — prev=5 — can decrement to 10 (10 > 5)")
        expect(!AlertValidation.canDecrement(threshold: 10, prevThreshold: 5),
               "10 — prev=5 — cannot decrement to 5 (5 not > 5, needs strict gap)")
        expect(!AlertValidation.canDecrement(threshold: 10, prevThreshold: 8),
               "10 — prev=8 — cannot decrement to 5 (5 < 8, would undercut prev)")
        expect(AlertValidation.canDecrement(threshold: 20, prevThreshold: 10),
               "20 — prev=10 — can decrement to 15 (15 > 10)")
        expect(!AlertValidation.canDecrement(threshold: 15, prevThreshold: 10),
               "15 — prev=10 — cannot decrement to 10 (10 not > 10)")
    }
}

// MARK: - AlertValidation.canIncrement

func testCanIncrement() {
    section("AlertValidation.canIncrement") {
        // Absolute ceiling
        expect(!AlertValidation.canIncrement(threshold: 100, nextThreshold: nil),
               "100 — no next — cannot increment (already at ceiling)")
        expect(!AlertValidation.canIncrement(threshold: 100, nextThreshold: 105),
               "100 — next=105 — cannot increment (at ceiling)")

        // Free increments (no next)
        expect(AlertValidation.canIncrement(threshold: 95, nextThreshold: nil),
               "95 — no next — can increment to 100")
        expect(AlertValidation.canIncrement(threshold: 5, nextThreshold: nil),
               "5 — no next — can increment")

        // Ordering constraint
        expect(AlertValidation.canIncrement(threshold: 80, nextThreshold: 90),
               "80 — next=90 — can increment to 85 (85 < 90)")
        expect(!AlertValidation.canIncrement(threshold: 85, nextThreshold: 90),
               "85 — next=90 — cannot increment to 90 (90 not < 90, needs strict gap)")
        expect(!AlertValidation.canIncrement(threshold: 88, nextThreshold: 90),
               "88 — next=90 — cannot increment to 93... wait threshold steps by 5: 88+5=93 < 90? no 93>90 → blocked")
        expect(AlertValidation.canIncrement(threshold: 80, nextThreshold: 100),
               "80 — next=100 — can increment to 85 (85 < 100)")
        expect(!AlertValidation.canIncrement(threshold: 95, nextThreshold: 100),
               "95 — next=100 — cannot increment to 100 (100 not < 100)")
    }
}

// MARK: - AlertValidation.defaultThreshold

func testDefaultThreshold() {
    section("AlertValidation.defaultThreshold") {
        // Empty tab
        expectEqual(AlertValidation.defaultThreshold(forTab: .hour, existing: []),
                    80, "empty tab defaults to 80")

        // One alert
        let one = [makeAlert(.hour, 70)]
        expectEqual(AlertValidation.defaultThreshold(forTab: .hour, existing: one),
                    75, "one alert at 70 → default 75")

        // Highest alert at 95
        let high = [makeAlert(.hour, 70), makeAlert(.hour, 95)]
        expectEqual(AlertValidation.defaultThreshold(forTab: .hour, existing: high),
                    100, "highest at 95 → default 100")

        // Highest already at 100 → clamps to 100
        let full = [makeAlert(.hour, 100)]
        expectEqual(AlertValidation.defaultThreshold(forTab: .hour, existing: full),
                    100, "highest at 100 → clamps to 100")

        // Cross-window: week alerts don't affect 5h default
        let weekOnly = [makeAlert(.week, 60)]
        expectEqual(AlertValidation.defaultThreshold(forTab: .hour, existing: weekOnly),
                    80, "week alerts ignored when computing 5h default")
    }
}

// MARK: - AlertValidation.sortedTabPairs

func testSortedTabPairs() {
    section("AlertValidation.sortedTabPairs") {
        let alerts: [UsageAlert] = [
            makeAlert(.hour, 90),
            makeAlert(.week, 70),
            makeAlert(.hour, 60),
            makeAlert(.hour, 80),
        ]

        let hourPairs = AlertValidation.sortedTabPairs(in: alerts, tab: .hour)
        expectEqual(hourPairs.count, 3, "3 hour alerts found")
        expectEqual(hourPairs[0].element.threshold, 60, "hour pair[0] = 60")
        expectEqual(hourPairs[1].element.threshold, 80, "hour pair[1] = 80")
        expectEqual(hourPairs[2].element.threshold, 90, "hour pair[2] = 90")

        let weekPairs = AlertValidation.sortedTabPairs(in: alerts, tab: .week)
        expectEqual(weekPairs.count, 1, "1 week alert found")
        expectEqual(weekPairs[0].element.threshold, 70, "week pair[0] = 70")

        // Offset indices point back into original array
        expect(alerts[hourPairs[0].offset].threshold == 60, "offset[0] points to threshold 60")
        expect(alerts[hourPairs[1].offset].threshold == 80, "offset[1] points to threshold 80")

        // Empty
        let empty = AlertValidation.sortedTabPairs(in: [], tab: .hour)
        expect(empty.isEmpty, "empty alerts → empty pairs")
    }
}

// MARK: - AlertService.check

// Applies AlertValidation.evaluate and returns the updated alerted set.
private func applyEvaluate(stats: UsageStats, alerts: [UsageAlert], alerted: Set<String>) -> Set<String> {
    let result = AlertValidation.evaluate(stats: stats, alerts: alerts, alerted: alerted)
    var updated = alerted
    result.toArm.forEach { updated.insert($0) }
    result.toDisarm.forEach { updated.remove($0) }
    return updated
}

func testAlertEvaluate() {
    section("AlertValidation.evaluate — firing") {
        var alerted = Set<String>()

        // Empty alerts: nothing
        alerted = applyEvaluate(stats: makeStats(hourPct: 95), alerts: [], alerted: alerted)
        expect(alerted.isEmpty, "empty alerts → alerted stays empty")

        // Threshold not met
        let alert = makeAlert(.hour, 80)
        alerted = applyEvaluate(stats: makeStats(hourPct: 75), alerts: [alert], alerted: alerted)
        expect(alerted.isEmpty, "75% < 80 → nothing fires")

        // Exactly at threshold
        alerted = applyEvaluate(stats: makeStats(hourPct: 80), alerts: [alert], alerted: alerted)
        expect(alerted.contains("hour-80"), "80% >= 80 → armed, key=hour-80")

        // Already armed: no duplicate
        let sizeBefore = alerted.count
        alerted = applyEvaluate(stats: makeStats(hourPct: 90), alerts: [alert], alerted: alerted)
        expectEqual(alerted.count, sizeBefore, "already armed at 90% → no duplicate")

        // Drops 4% below (79 < 80 but > 80-5=75): stays armed
        alerted = applyEvaluate(stats: makeStats(hourPct: 76), alerts: [alert], alerted: alerted)
        expect(alerted.contains("hour-80"), "76% only 4% below → still armed")

        // Drops exactly 5% below: re-arms
        alerted = applyEvaluate(stats: makeStats(hourPct: 74.9), alerts: [alert], alerted: alerted)
        expect(!alerted.contains("hour-80"), "74.9% > 5% below 80 → re-armed")

        // Fires again after re-arm
        alerted = applyEvaluate(stats: makeStats(hourPct: 85), alerts: [alert], alerted: alerted)
        expect(alerted.contains("hour-80"), "fires again after re-arm")
    }

    section("AlertValidation.evaluate — toFire contents") {
        let alert = makeAlert(.hour, 80)
        let result = AlertValidation.evaluate(
            stats: makeStats(hourPct: 85), alerts: [alert], alerted: [])
        expectEqual(result.toFire.count, 1, "one item to fire")
        expectEqual(result.toArm.count, 1, "one key to arm")
        expectEqual(result.toArm.first, "hour-80", "arm key = hour-80")
        expect(result.toFire.first?.pct == 85, "toFire pct = 85")
        expect(result.toFire.first?.alert.window == .hour, "toFire window = .hour")

        // Already armed: nothing to fire
        let result2 = AlertValidation.evaluate(
            stats: makeStats(hourPct: 90), alerts: [alert], alerted: ["hour-80"])
        expect(result2.toFire.isEmpty, "already armed → nothing to fire")
        expect(result2.toArm.isEmpty, "already armed → nothing to arm")
    }

    section("AlertValidation.evaluate — multiple alerts same window") {
        var alerted = Set<String>()
        let a70 = makeAlert(.hour, 70)
        let a90 = makeAlert(.hour, 90)
        let alerts = [a70, a90]

        alerted = applyEvaluate(stats: makeStats(hourPct: 60), alerts: alerts, alerted: alerted)
        expect(alerted.isEmpty, "60% → neither fires")

        alerted = applyEvaluate(stats: makeStats(hourPct: 75), alerts: alerts, alerted: alerted)
        expect(alerted.contains("hour-70"), "75% → 70 fires")
        expect(!alerted.contains("hour-90"), "75% → 90 does not fire")

        alerted = applyEvaluate(stats: makeStats(hourPct: 95), alerts: alerts, alerted: alerted)
        expect(alerted.contains("hour-70"), "95% → 70 still armed")
        expect(alerted.contains("hour-90"), "95% → 90 now fires")

        alerted = applyEvaluate(stats: makeStats(hourPct: 64), alerts: alerts, alerted: alerted)
        expect(!alerted.contains("hour-70"), "64% < 65 (70-5) → 70 re-armed")
        // 64 < 85 (90-5) so 90 also re-arms
        expect(!alerted.contains("hour-90"), "64% < 85 (90-5) → 90 also re-armed")

        // Re-verify: 80% re-arms 70 but NOT 90 (80 < 65? no; 80 < 85? yes → 90 re-arms too)
        // Use 87% to confirm only 90 arms (87 >= 70 → 70 re-fires, 87 < 90 → 90 stays off)
        alerted = applyEvaluate(stats: makeStats(hourPct: 87), alerts: alerts, alerted: alerted)
        expect(alerted.contains("hour-70"), "87% >= 70 → 70 fires again after re-arm")
        expect(!alerted.contains("hour-90"), "87% < 90 → 90 does not fire")
    }

    section("AlertValidation.evaluate — week window") {
        var alerted = Set<String>()
        let wk = makeAlert(.week, 80)
        alerted = applyEvaluate(stats: makeStats(weekPct: 85), alerts: [wk], alerted: alerted)
        expect(alerted.contains("week-80"), "week alert fires using week stat")
        expect(!alerted.contains("hour-80"), "week alert does not pollute hour key")
    }

    section("AlertValidation.evaluate — unavailable window skipped") {
        let alert = makeAlert(.hour, 50)
        let result = AlertValidation.evaluate(
            stats: makeStats(hourPct: 95, hourAvail: false),
            alerts: [alert], alerted: [])
        expect(result.toFire.isEmpty, "unavailable window → nothing to fire")
        expect(result.toArm.isEmpty, "unavailable window → nothing to arm")
    }

    section("AlertValidation.evaluate — cross-window isolation") {
        var alerted = Set<String>()
        let hourAlert = makeAlert(.hour, 80)
        let weekAlert = makeAlert(.week, 80)
        alerted = applyEvaluate(
            stats: makeStats(hourPct: 90, weekPct: 10),
            alerts: [hourAlert, weekAlert], alerted: alerted)
        expect(alerted.contains("hour-80"), "hour alert fires")
        expect(!alerted.contains("week-80"), "week alert does not fire (week at 10%)")
    }

    section("AlertValidation.evaluate — key format") {
        let a = makeAlert(.hour, 95)
        let r1 = AlertValidation.evaluate(stats: makeStats(hourPct: 100), alerts: [a], alerted: [])
        expect(r1.toArm.contains("hour-95"), "key format: hour-95")

        let b = makeAlert(.week, 5)
        let r2 = AlertValidation.evaluate(stats: makeStats(weekPct: 10), alerts: [b], alerted: [])
        expect(r2.toArm.contains("week-5"), "key format: week-5")
    }

    section("AlertValidation.evaluate — re-arm only when in alerted set") {
        let alert = makeAlert(.hour, 80)
        // Below threshold but not currently armed → disarm list stays empty
        let r = AlertValidation.evaluate(
            stats: makeStats(hourPct: 70), alerts: [alert], alerted: [])
        expect(r.toDisarm.isEmpty, "not armed + below threshold → nothing to disarm")

        // Below threshold and armed → disarm
        let r2 = AlertValidation.evaluate(
            stats: makeStats(hourPct: 70), alerts: [alert], alerted: ["hour-80"])
        expect(r2.toDisarm.contains("hour-80"), "armed + 10% below → disarm")
    }
}

// MARK: - Run all

@main struct TestRunner {
    static func main() {
        testAlertWindow()
        testUsageAlert()
        testCanDecrement()
        testCanIncrement()
        testDefaultThreshold()
        testSortedTabPairs()
        testAlertEvaluate()

        print("\n────────────────────────────────────")
        print("Results: \(passed) passed, \(failed) failed")
        if failed > 0 {
            print("FAIL")
            exit(1)
        } else {
            print("PASS")
        }
    }
}
