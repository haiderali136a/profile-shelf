import XCTest
@testable import DockCore

final class ProfileSwitchPolicyTests: XCTestCase {
    func testAllSameProviderOpponentsAreClosedIncludingHiddenProfiles() {
        let processes = [ProfileSwitchProcess(pid: 3, provider: .codex, profileID: "personal"),
                         ProfileSwitchProcess(pid: 2, provider: .codex, profileID: "hidden-client"),
                         ProfileSwitchProcess(pid: 4, provider: .claude, profileID: "claude-work")]
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: processes), .quit([2, 3]))
    }
    func testAlongsideNeverRequestsQuit() {
        let processes = [ProfileSwitchProcess(pid: 1, provider: .claude, profileID: "personal")]
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .claude, mode: .alongside, processes: processes), .open)
    }
    func testOpenTargetFocusesWithoutClosingIntentionalParallelWork() {
        let processes = [ProfileSwitchProcess(pid: 1, provider: .claude, profileID: "personal"),
                         ProfileSwitchProcess(pid: 2, provider: .claude, profileID: "work")]
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .claude, mode: .switchProfile, processes: processes), .focus)
    }
    func testUnassignedProcessBlocksSwitch() {
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile,
            processes: [ProfileSwitchProcess(pid: 1, provider: .codex, profileID: nil)]), .blocked)
    }
    func testUnresolvedSnapshotBlocksSwitchBeforeQuit() {
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [], unresolved: true), .blocked)
    }
    func testPendingLaunchBlocksSwitch() {
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .claude, mode: .switchProfile, processes: [], pending: true), .blocked)
    }
    func testDuplicateSnapshotPIDsDoNotProduceDuplicateQuitRequests() {
        let process = ProfileSwitchProcess(pid: 7, provider: .codex, profileID: "personal")
        XCTAssertEqual(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [process, process]), .quit([7]))
    }
    func testQuitDelayNeverBecomesReadyWhileCapturedProcessIsAlive() {
        XCTAssertEqual(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [7], stillRunning: [7], processes: []), .waiting)
    }
    func testUnexpectedNewAccountStopsTheSwitch() {
        let new = ProfileSwitchProcess(pid: 8, provider: .codex, profileID: "new-account")
        XCTAssertEqual(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [7], stillRunning: [], processes: [new]), .changed)
    }
    func testOtherProviderMayKeepRunning() {
        let other = ProfileSwitchProcess(pid: 9, provider: .claude, profileID: "personal")
        XCTAssertEqual(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [7], stillRunning: [], processes: [other]), .ready)
    }
    func testTransientIdentityReadFailureDuringShutdownWaitsInsteadOfLaunching() {
        XCTAssertEqual(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .claude, originalPIDs: [7], stillRunning: [], processes: [], unresolved: true), .waiting)
    }
    func testCapturedExitingProcessCanLoseOwnershipWithoutAborting() {
        let exiting = ProfileSwitchProcess(pid: 7, provider: .codex, profileID: nil)
        XCTAssertEqual(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex,
            originalPIDs: [7], stillRunning: [7], processes: [exiting], unresolved: true), .waiting)
    }
    func testBriefStartupThenCrashIsNotConfirmed() {
        var confirmation = ProfileLaunchConfirmation()
        XCTAssertFalse(confirmation.observe(pids: [10], readable: true, at: 0))
        XCTAssertFalse(confirmation.observe(pids: [], readable: true, at: 0.5))
        XCTAssertFalse(confirmation.observe(pids: [11], readable: true, at: 2))
        XCTAssertFalse(confirmation.observe(pids: [11], readable: true, at: 2.9))
        XCTAssertTrue(confirmation.observe(pids: [11], readable: true, at: 3.1))
    }
    func testEarlyLauncherCompletionDoesNotEndAccountObservation() {
        var confirmation = ProfileLaunchConfirmation()
        XCTAssertFalse(confirmation.observe(pids: [], readable: true, at: 0))
        XCTAssertFalse(confirmation.observe(pids: [], readable: true, at: 1))
        XCTAssertFalse(confirmation.observe(pids: [10], readable: true, at: 2))
        XCTAssertTrue(confirmation.observe(pids: [10], readable: true, at: 3.1))
    }
    func testUnreadableOrChangedPIDRestartsConfirmation() {
        var confirmation = ProfileLaunchConfirmation()
        XCTAssertFalse(confirmation.observe(pids: [10], readable: true, at: 0))
        XCTAssertFalse(confirmation.observe(pids: [10], readable: false, at: 2))
        XCTAssertFalse(confirmation.observe(pids: [10], readable: true, at: 3))
        XCTAssertFalse(confirmation.observe(pids: [11], readable: true, at: 4))
        XCTAssertTrue(confirmation.observe(pids: [11], readable: true, at: 5.1))
    }
    func testNoAccountCountsOrEmailAssumptions() {
        let many = (1...500).map { ProfileSwitchProcess(pid: Int32($0), provider: .claude, profileID: "account-\($0)") }
        if case .quit(let ids) = ProfileSwitchPolicy.plan(targetID: "another", provider: .claude, mode: .switchProfile, processes: many) {
            XCTAssertEqual(ids.count, 500)
        } else { XCTFail("Expected verified same-provider quit list") }
    }
}
