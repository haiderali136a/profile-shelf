import XCTest
@testable import DockCore

final class ClaudeUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_164_800)
    func testAccountWindowsAndUnavailableResetSurface() throws {
        let data = Data(#"{"five_hour":{"utilization":35,"resets_at":"2026-09-23T13:59:59.737374+00:00"},"seven_day":{"utilization":10,"resets_at":"2026-09-25T22:59:59Z"},"cedar_ember":{"eligible":false,"ineligible_reason":"surface","grants":[]}}"#.utf8)
        let snapshot = try ClaudeUsageParser.parse(data, identity: "fixture", plan: "max", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [90, 65])
        XCTAssertEqual(snapshot.windows.map(\.title), ["Week", "5 hours"])
        XCTAssertNotNil(snapshot.windows.last?.resetsAt)
        XCTAssertNil(snapshot.bankedResets, "An unavailable reset surface does not mean zero resets")
    }

    func testMissingAndInvalidMeasurementsNeverBecomeZeroUsage() throws {
        for payload in [#"{}"#, #"{"five_hour":{"utilization":false,"resets_at":"2026-09-25T00:00:00Z"}}"#, #"{"five_hour":{"utilization":0,"resets_at":"bad"}}"#] {
            XCTAssertThrowsError(try ClaudeUsageParser.parse(Data(payload.utf8), identity: "fixture", plan: nil, fetchedAt: now))
        }
    }

    func testExplicitZeroIdleSessionAcceptsMissingOrNullReset() throws {
        for fiveHour in [#"{"utilization":0}"#, #"{"utilization":0,"resets_at":null}"#] {
            let json = #"{"five_hour":\#(fiveHour),"seven_day":{"utilization":62,"resets_at":"2026-09-25T00:00:00Z"}}"#
            let snapshot = try ClaudeUsageParser.parse(Data(json.utf8), identity: "fixture", plan: "team", fetchedAt: now)
            let session = try XCTUnwrap(snapshot.windows.first { $0.duration == 18000 })
            XCTAssertEqual(session.usedPercent, 0)
            XCTAssertNil(session.resetsAt)
            XCTAssertFalse(snapshot.hasUnparsedWindows)
            XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot, expectedIdentity: "fixture", now: now).compact, "5h 0%  7d 62%")
        }
    }
    func testIdleSessionAloneIsStillAValidReadingWithoutInventingAWeek() throws {
        let snapshot = try ClaudeUsageParser.parse(Data(#"{"five_hour":{"utilization":0,"resets_at":null}}"#.utf8), identity: "fixture", plan: "team", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 0)
        XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot, expectedIdentity: "fixture", now: now).compact, "5h 0%")
    }
    func testAbsentOrNullSessionDoesNotInventZero() throws {
        for payload in [#"{"seven_day":{"utilization":62,"resets_at":"2026-09-25T00:00:00Z"}}"#, #"{"five_hour":null,"seven_day":{"utilization":62,"resets_at":"2026-09-25T00:00:00Z"}}"#] {
            let snapshot = try ClaudeUsageParser.parse(Data(payload.utf8), identity: "fixture", plan: "team", fetchedAt: now)
            XCTAssertEqual(snapshot.windows.map(\.duration), [604800])
            XCTAssertEqual(MenuBarQuotaFormatter.format(snapshot, expectedIdentity: "fixture", now: now).compact, "7d 62%")
        }
    }
    func testMissingBooleanAndMalformedUtilizationAreNotIdleZero() throws {
        for measurement in [#"{"resets_at":null}"#, #"{"utilization":null,"resets_at":null}"#, #"{"utilization":false,"resets_at":null}"#, #"{"utilization":"0","resets_at":null}"#, #"{"utilization":-1,"resets_at":null}"#] {
            let payload = #"{"five_hour":\#(measurement)}"#
            XCTAssertThrowsError(try ClaudeUsageParser.parse(Data(payload.utf8), identity: "fixture", plan: "team", fetchedAt: now))
        }
    }
    func testInvalidResetAndPositiveUsageWithoutResetStayFlagged() throws {
        for measurement in [#"{"utilization":0,"resets_at":"bad"}"#, #"{"utilization":0,"resets_at":42}"#, #"{"utilization":5,"resets_at":null}"#] {
            let payload = #"{"five_hour":\#(measurement),"seven_day":{"utilization":63,"resets_at":"2026-09-25T00:00:00Z"}}"#
            let snapshot = try ClaudeUsageParser.parse(Data(payload.utf8), identity: "fixture", plan: "team", fetchedAt: now)
            XCTAssertTrue(snapshot.hasUnparsedWindows)
            XCTAssertEqual(snapshot.windows.map(\.duration), [604800])
        }
    }

    func testBankedResetsIncludeSavedGrantNotYetUsableAndExcludeExpiredOrFutureGrants() throws {
        let grant: [String: Any] = ["id": "saved", "resets_left": 1, "starts_at": "2026-01-01T00:00:00Z", "ends_at": "2027-01-01T00:00:00Z", "usable_now": false, "use_requires_limit": true]
        var expired = grant; expired["id"] = "expired"; expired["ends_at"] = "2026-01-02T00:00:00Z"
        var future = grant; future["id"] = "future"; future["starts_at"] = "2027-01-01T00:00:00Z"
        let inventory = try XCTUnwrap(ClaudeUsageParser.resets(["eligible": true, "grants": [grant, expired, future]], now: now))
        XCTAssertEqual(inventory.count, 1)
        XCTAssertEqual(inventory.usable, 0)
        XCTAssertEqual(inventory.expiries.count, 1)
        XCTAssertNil(ClaudeUsageParser.resets(["eligible": true, "grants": [grant, grant]], now: now))
        var malformed = grant; malformed["resets_left"] = true
        XCTAssertNil(ClaudeUsageParser.resets(["eligible": true, "grants": [malformed]], now: now))
        XCTAssertEqual(ClaudeUsageParser.resets(["eligible": true, "grants": []], now: now)?.count, 0)
        XCTAssertNil(ClaudeUsageParser.resets(["eligible": true], now: now))
    }
}
