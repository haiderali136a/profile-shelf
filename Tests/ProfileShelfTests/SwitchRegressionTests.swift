import XCTest
import DockCore
@testable import ProfileShelf

final class SwitchRegressionTests: XCTestCase {
    @MainActor func testOldCompletionCannotClearNewAttemptOrItsErrors() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DockModel(home: root)
        model.preferences.switchDiagnosticsEnabled = false
        let profile = Profile(id: "fixture", name: "Work", color: "377CF6")
        let old = model.beginDesktopLaunch(profile)
        let current = model.beginDesktopLaunch(profile)
        model.completeDesktopLaunch(profile, token: old, error: "old failure")
        XCTAssertTrue(model.desktopLaunchInFlight.contains(profile.id))
        XCTAssertNil(model.desktopLaunchErrors[profile.id])
        model.completeDesktopLaunch(profile, token: current)
        XCTAssertFalse(model.desktopLaunchInFlight.contains(profile.id))
        XCTAssertNil(model.desktopLaunchErrors[profile.id])
    }
    @MainActor func testOldTimeoutCannotClearNewOpeningAndHungLauncherBlocksRetry() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DockModel(home: root)
        model.preferences.switchDiagnosticsEnabled = false
        let profile = Profile(id: "work", name: "Work", color: "377CF6")
        let old = model.beginDesktopLaunch(profile)
        let current = model.beginDesktopLaunch(profile)
        model.opening.insert(profile.id)
        model.desktopLaunchTimedOut(profile, token: old)
        XCTAssertTrue(model.opening.contains(profile.id))
        XCTAssertNil(model.desktopLaunchErrors[profile.id])
        model.desktopLaunchTimedOut(profile, token: current)
        XCTAssertFalse(model.opening.contains(profile.id))
        XCTAssertNotNil(model.desktopLaunchErrors[profile.id])
        XCTAssertFalse(model.canOpenAlongside(profile))
        XCTAssertTrue(model.desktopLaunchInFlight.contains(profile.id))
    }
    @MainActor func testAlongsideIsUnavailableDuringProviderSwitchOrLaunch() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DockModel(home: root)
        model.preferences.switchDiagnosticsEnabled = false
        let work = Profile(id: "fixture", name: "Work", color: "377CF6")
        XCTAssertTrue(model.canOpenAlongside(work))
        let token = model.beginDesktopLaunch(work)
        XCTAssertFalse(model.canOpenAlongside(work))
        model.completeDesktopLaunch(work, token: token)
        model.switchingTargets[.codex] = "different-profile"
        XCTAssertFalse(model.canOpenAlongside(work))
        model.switchingTargets[.codex] = nil
        model.closing.insert(work.id)
        XCTAssertFalse(model.canOpenAlongside(work))
    }
    @MainActor func testCurrentLaunchErrorIsVisibleAndDoesNotResetAnotherProfile() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DockModel(home: root)
        model.preferences.switchDiagnosticsEnabled = false
        let personal = Profile(id: "personal", name: "Personal", color: "377CF6")
        let work = Profile(id: "work", name: "Work", color: "377CF6")
        let personalToken = model.beginDesktopLaunch(personal)
        let workToken = model.beginDesktopLaunch(work)
        model.opening.formUnion([personal.id, work.id])
        model.completeDesktopLaunch(work, token: workToken, error: "fixture launcher failure")
        XCTAssertEqual(model.message, "fixture launcher failure")
        XCTAssertEqual(model.messageRecovery?.profileID, work.id)
        XCTAssertTrue(model.opening.contains(personal.id))
        XCTAssertTrue(model.desktopLaunchInFlight.contains(personal.id))
        XCTAssertFalse(model.opening.contains(work.id))
        model.completeDesktopLaunch(personal, token: personalToken)
    }
}
