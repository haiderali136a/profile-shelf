import XCTest
@testable import DockCore

final class UsageFreshnessTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testRecentMinuteHourDayReadings() {
        XCTAssertEqual(UsageFreshness.label(fetchedAt: now, now: now), "Updated just now")
        XCTAssertEqual(UsageFreshness.label(fetchedAt: now.addingTimeInterval(-120), now: now), "Updated 2m ago")
        XCTAssertEqual(UsageFreshness.label(fetchedAt: now.addingTimeInterval(-7200), now: now), "Updated 2h ago")
        XCTAssertEqual(UsageFreshness.label(fetchedAt: now.addingTimeInterval(-172800), now: now), "Updated 2d ago")
    }
    func testInvalidOrFutureTimesAreNotReportedAsFresh() {
        for date in [now.addingTimeInterval(120), Date(timeIntervalSince1970: .infinity), now.addingTimeInterval(-400 * 86400)] {
            XCTAssertEqual(UsageFreshness.label(fetchedAt: date, now: now), "Reading time unavailable")
        }
    }
}
