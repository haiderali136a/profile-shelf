import XCTest
import DockCore
@testable import ProfileShelf

final class ProfilePresentationTests: XCTestCase {
    func testActivityConnectionStatesAreNotReplacedByOpen() {
        for issue in [ActivityConnectionIssue.connecting, .reconnecting, .metadata, .unsupported] {
            let summary = ActivitySummary(appOpen: true, connectionIssue: issue)
            XCTAssertEqual(summary.profileStatusText, issue.label)
        }
        XCTAssertEqual(ActivitySummary(appOpen: true).profileStatusText, "Activity unavailable")
        XCTAssertEqual(ActivitySummary(liveAvailable: true).profileStatusText, "Results unknown")
        XCTAssertNil(ActivitySummary(unread: 0, liveAvailable: true, appOpen: true).profileStatusText)
    }

    func testSimultaneousActivityAndUnreadRemainAvailable() {
        let summary = ActivitySummary(unread: 3, working: 2, waiting: 1, liveAvailable: true, appOpen: true)
        XCTAssertEqual(summary.profileStatusText, "2 working · 1 waiting")
        XCTAssertEqual(summary.badge, "3", "Compact passes the same summary to ProfileBadge as Full")
        XCTAssertEqual(ActivitySummary(unread: 4, working: 1).profileStatusText, "1 working")
        XCTAssertEqual(ActivitySummary(unread: 4).profileStatusText, "4 unread")
        XCTAssertEqual(ActivitySummary(waiting: 1).profileStatusText, "1 needs you")
    }

    func testRenewableTokenOffersRefreshBeforeReconnect() {
        XCTAssertEqual(UsageRecoveryAction.actions(for: .claudeTokenStale), [.refresh, .reconnect])
        for error in [UsageLoadError.notSignedIn, .authorizationRequired, .claudeSignInRequired, .claudeConnectionNeeded, .claudeOtherAccount] {
            XCTAssertEqual(UsageRecoveryAction.actions(for: error), [.reconnect])
        }
        for error in [UsageLoadError.network, .wrongAccount, .invalidResponse, .rateLimited(Date())] {
            XCTAssertEqual(UsageRecoveryAction.actions(for: error), [.refresh])
        }
    }

    func testQuickWindowIncludesEveryDisplayedProviderAndPreservesOrder() {
        let providers: [ProfileProvider] = [.agent, .codex, .claude, .claudeCode, .terminal, .agent]
        let profiles = providers.enumerated().map { index, kind in
            var profile = Profile(id: "fixture-\(index)", name: index == 0 ? "Antigravity" : "Profile \(index)", color: "377CF6")
            profile.provider = kind
            return profile
        }
        let sections = QuickProfileSection.sections(profiles: profiles, query: "")
        XCTAssertEqual(Set(sections.flatMap(\.profiles).map(\.id)), Set(profiles.map(\.id)))
        XCTAssertEqual(sections.first(where: { $0.id == .agent })?.profiles.map(\.id), ["fixture-0", "fixture-5"])
        let result = QuickProfileSection.sections(profiles: profiles, query: "ANTIGRAVITY")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.profiles.map(\.id), ["fixture-0"])
        XCTAssertTrue(QuickProfileSection.sections(profiles: profiles, query: "no match").isEmpty)
    }

    @MainActor func testQuickWindowRespectsHiddenProfilePreference() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home)
        var visible = Profile(id: "visible", name: "Antigravity", color: "377CF6")
        visible.provider = .agent; visible.agentID = "antigravity"
        var hidden = visible; hidden.id = "hidden"; hidden.hiddenFromStrip = true
        model.preferences.profiles = [visible, hidden]
        let sections = QuickProfileSection.sections(profiles: model.displayedProfiles, query: "")
        XCTAssertEqual(sections.first(where: { $0.id == .agent })?.profiles.map(\.id), ["visible"])
    }
    func testMenuBarTracksRememberedAccountsWithoutCombiningFourProfiles() {
        let personal = Profile(id: "g-personal", name: "ChatGPT Personal", color: "377CF6")
        let work = Profile(id: "g-work", name: "ChatGPT Work", color: "377CF6")
        var cp = Profile(id: "c-personal", name: "Claude Personal", color: "D7825A"); cp.provider = .claude
        var cw = Profile(id: "c-work", name: "Claude Work", color: "D7825A"); cw.provider = .claude
        let result = MenuBarProfileSelection.profiles(from: [personal, work, cp, cw], remembered: ["codex": work.id, "claude": cw.id], running: [personal.id, cp.id])
        XCTAssertEqual(result.map(\.id), [work.id, cw.id], "Remembered accounts are stable even when another account is open")
        XCTAssertEqual(result.map(\.name), ["ChatGPT Work", "Claude Work"])
    }

    func testMenuBarFallsBackAfterTrackedAccountIsHiddenOrRemoved() {
        let first = Profile(id: "first", name: "First", color: "377CF6")
        let running = Profile(id: "running", name: "Running", color: "377CF6")
        let result = MenuBarProfileSelection.profiles(from: [first, running], remembered: ["codex": "no-longer-visible"], running: [running.id])
        XCTAssertEqual(result.map(\.id), [running.id])
        XCTAssertEqual(MenuBarProfileSelection.profiles(from: [first, running], remembered: [:], running: []).map(\.id), [first.id])
        XCTAssertTrue(MenuBarProfileSelection.profiles(from: [], remembered: [:], running: []).isEmpty)
    }

}
