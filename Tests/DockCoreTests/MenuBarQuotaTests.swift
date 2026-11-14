import XCTest
@testable import DockCore

final class MenuBarQuotaTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snapshot(identity: String = "a", age: TimeInterval = 0, windows: [UsageWindow]? = nil, partial: Bool = false) -> UsageSnapshot {
        UsageSnapshot(identity: identity, plan: "test", windows: windows ?? [
            UsageWindow(id: "week", duration: 604800, usedPercent: 63, resetsAt: now.addingTimeInterval(86400)),
            UsageWindow(id: "session", duration: 18000, usedPercent: 12, resetsAt: now.addingTimeInterval(3600))
        ], bankedResets: nil, applicableResets: nil, resetExpiries: nil, fetchedAt: now.addingTimeInterval(-age), hasUnparsedWindows: partial)
    }
    func testUnknownIsNotZero() {
        let value = MenuBarQuotaFormatter.format(nil, expectedIdentity: nil, now: now)
        XCTAssertEqual(value.compact, "—")
        XCTAssertFalse(value.detail.contains("0%"))
    }
    func testWrongAccountNeverShowsCachedCounters() {
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot(identity: "other"), expectedIdentity: "a", now: now).compact, "—")
    }
    func testIdentityMustBeKnown() {
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot(), expectedIdentity: nil, now: now).compact, "—")
    }
    func testIdentityValidationSuppressesOldAccount() {
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot(), expectedIdentity: "a", validating: true, now: now).compact, "checking")
    }
    func testWindowsAreDurationLabelledAndOrdered() {
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot(), expectedIdentity: "a", now: now).compact, "5h 12%  7d 63%")
    }
    func testStaleCountersAreMarked() {
        let result = MenuBarQuotaFormatter.format(snapshot(age: 500), expectedIdentity: "a", now: now)
        XCTAssertTrue(result.stale); XCTAssertTrue(result.compact.hasPrefix("~"))
    }
    func testNetworkErrorKeepsReadingButMarksItStale() {
        XCTAssertTrue(MenuBarQuotaFormatter.format(snapshot(), expectedIdentity: "a", hasError: true, now: now).stale)
    }
    func testFailedRequestWithoutPriorReadingNeverDisplaysZero() {
        let result = MenuBarQuotaFormatter.format(nil, expectedIdentity: "a", hasError: true, now: now)
        XCTAssertEqual(result.compact, "—")
        XCTAssertFalse(result.detail.contains("0%"))
    }
    func testCachedExplicitZeroAfterFailureIsMarkedStale() {
        let zero = [UsageWindow(id: "five_hour", duration: 18000, usedPercent: 0, resetsAt: nil)]
        let result = MenuBarQuotaFormatter.format(snapshot(windows: zero), expectedIdentity: "a", hasError: true, now: now)
        XCTAssertTrue(result.stale)
        XCTAssertEqual(result.compact, "~5h 0%")
        XCTAssertTrue(result.detail.contains("stale"))
    }
    func testStatusLineIsExplicitlyDifferentSource() {
        let result = MenuBarQuotaFormatter.format(snapshot(), expectedIdentity: "a", now: now, statusLine: true)
        XCTAssertTrue(result.compact.hasPrefix("†")); XCTAssertTrue(result.detail.contains("not an independently verified"))
    }
    func testPartialSchemaIsVisible() {
        XCTAssertTrue(MenuBarQuotaFormatter.format(snapshot(partial: true), expectedIdentity: "a", now: now).compact.hasSuffix("?"))
    }
    func testMalformedNumbersNeverReachIntegerConversion() {
        let invalid = [UsageWindow(id: "bad", duration: .infinity, usedPercent: 20, resetsAt: nil),
                       UsageWindow(id: "bad2", duration: 18000, usedPercent: .nan, resetsAt: nil),
                       UsageWindow(id: "bad3", duration: Double.greatestFiniteMagnitude, usedPercent: 20, resetsAt: nil)]
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot(windows: invalid), expectedIdentity: "a", now: now).compact, "—")
    }
    func testNonstandardWindowDoesNotPretendToBeFiveHours() {
        let three = [UsageWindow(id: "short", duration: 10800, usedPercent: 7, resetsAt: nil)]
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot(windows: three), expectedIdentity: "a", now: now).compact, "3h 7%")
    }
    func testResetDoesNotReplaceActualPercentWithAssumedZero() {
        let old = [UsageWindow(id: "short", duration: 18000, usedPercent: 99, resetsAt: now.addingTimeInterval(-1))]
        XCTAssertTrue(MenuBarQuotaFormatter.format(snapshot(windows: old), expectedIdentity: "a", now: now).compact.contains("99%"))
    }
}
