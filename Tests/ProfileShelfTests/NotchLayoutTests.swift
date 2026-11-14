import XCTest
import AppKit
import DockCore
@testable import ProfileShelf

final class NotchLayoutTests: XCTestCase {
    @MainActor func testNativeControllerRestoresFullFrameAfterCompactDisclosure() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No attached screen") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home), fixture = FixtureUsageClient()
        model.preferences.profiles = (1...4).map { Profile(id: "fixture-\($0)", name: "Account \($0)", color: "377CF6") }
        let usage = UsageStore(client: fixture, claudeClient: fixture, home: home)
        let island = IslandController(screen: screen, model: model, usage: usage, presentWindows: false, reduceMotion: { true }, settings: {})
        defer { island.shutdown(); usage.shutdown() }
        let full = island.layout
        model.setNotchLayout(.compact); island.updateLayout()
        let compact = island.layout
        XCTAssertLessThan(compact.expanded.height, full.expanded.height)
        XCTAssertEqual(compact.collapsed, full.collapsed)
        island.presentation.toggleCompactUsage("fixture-1")
        XCTAssertGreaterThan(island.layout.expanded.height, compact.expanded.height)
        XCTAssertEqual(island.layout.profileRows, compact.profileRows)
        model.setNotchLayout(.full); island.updateLayout()
        XCTAssertEqual(island.layout, full, "Compact usage selection cannot change Full geometry")
        model.setNotchLayout(.compact); island.updateLayout()
        island.presentation.closeCompactUsage()
        XCTAssertEqual(island.layout, compact)
    }
    func testOldPreferencesAndUnknownLayoutRetainFull() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"profiles":[],"scale":1}"#.utf8))
        XCTAssertEqual(old.effectiveNotchLayout, .full)
        let future = try JSONDecoder().decode(Preferences.self, from: Data(#"{"profiles":[],"scale":1,"notchLayout":"future"}"#.utf8))
        XCTAssertEqual(future.effectiveNotchLayout, .full)
    }

    @MainActor func testSwitchingAndRevertingPreservesGridWidthsAndProfiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home)
        model.preferences.profiles = [Profile(id: "one", name: "Personal", color: "377CF6")]
        model.preferences.profileGrid = ProfileGrid(columns: 4, rows: 1)
        model.preferences.expandedWidth = 710; model.preferences.compactWidth = 240
        for mode in [NotchLayout.compact, .full] {
            model.setNotchLayout(mode)
            let stored = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: model.settingsURL))
            XCTAssertEqual(stored.effectiveNotchLayout, mode)
            XCTAssertEqual(stored.profileGrid, ProfileGrid(columns: 4, rows: 1))
            XCTAssertEqual(stored.expandedWidth, 710); XCTAssertEqual(stored.compactWidth, 240)
            XCTAssertEqual(stored.profiles.map(\.id), ["one"])
        }
        XCTAssertNil(model.preferences.notchLayout, "Reverting removes the density override")
    }

    @MainActor func testCompactDisclosureDoesNotModifyFullResetDisclosures() {
        let presentation = IslandPresentation()
        presentation.toggleResetDetails("full-account")
        presentation.toggleCompactUsage("one"); presentation.toggleCompactResets()
        XCTAssertTrue(presentation.compactResetExpanded)
        presentation.toggleCompactUsage("two")
        XCTAssertEqual(presentation.compactUsageProfileID, "two")
        XCTAssertFalse(presentation.compactResetExpanded)
        presentation.closeCompactUsage()
        XCTAssertNil(presentation.compactUsageProfileID)
        XCTAssertEqual(presentation.resetDetails, ["full-account"])
    }

    func testCompactReadingHidesUnvalidatedIdentityAndRetainsVerifiedPausedReading() {
        let now = Date(), snapshot = UsageSnapshot(identity: "fixture", plan: nil, windows: [UsageWindow(id: "week", duration: 604800, usedPercent: 70, resetsAt: nil), UsageWindow(id: "five", duration: 18000, usedPercent: 15, resetsAt: nil)], bankedResets: 0, applicableResets: 0, resetExpiries: [], fetchedAt: now)
        let validating = UsageEntry(snapshot: snapshot, validatingIdentity: true)
        XCTAssertNil(CompactNotchReading(entry: validating, statusLine: nil).snapshot)
        let entry = UsageEntry(snapshot: snapshot, validatingIdentity: false, error: .rateLimited(now.addingTimeInterval(300)))
        let reading = CompactNotchReading(entry: entry, statusLine: nil)
        XCTAssertEqual(reading.windows.map(\.duration), [18000, 604800])
        XCTAssertEqual(reading.windows.map(\.remainingPercent), [85, 30])
        XCTAssertTrue(reading.isStale(profile: Profile(id: "one", name: "One", color: "377CF6"), entry: entry, now: now))
        XCTAssertEqual(reading.snapshot, snapshot)
        XCTAssertNil(CompactNotchReading(entry: nil, statusLine: snapshot).snapshot, "Fallback requires the same error condition as Full")
        XCTAssertTrue(CompactNotchReading(entry: UsageEntry(error: .claudeConnectionNeeded), statusLine: snapshot).isStatusLine)
    }
}
