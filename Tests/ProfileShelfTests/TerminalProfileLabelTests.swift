import AppKit
import XCTest
import DockCore
@testable import ProfileShelf

final class TerminalProfileLabelTests: XCTestCase {
    func testReadableFallbackAndProjectFolder() {
        XCTAssertEqual(TerminalProfileLabel.name(agent: .claude, tty: "/dev/ttys007", project: nil), "Claude Code · 007")
        XCTAssertEqual(TerminalProfileLabel.name(agent: .claude, tty: "/dev/ttys012", project: nil), "Claude Code · 012")
        XCTAssertEqual(TerminalProfileLabel.name(agent: .claude, tty: "/dev/ttys007", project: "/work/my-project"), "Claude Code · my-project")
        XCTAssertEqual(TerminalProfileLabel.name(agent: .claude, tty: "/dev/ttys007", project: "/"), "Claude Code · 007")
    }

    @MainActor func testExistingAutomaticNameMigratesAndFollowsReportedProject() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home)
        var profile = Profile(id: "terminal-fixture", name: "Claude Code · Terminal 007", color: "D7825A")
        profile.provider = .terminal; profile.discoveredTerminal = true; profile.terminalAgent = .claude
        profile.projectPath = "/saved/launch-folder"
        profile.terminalTTY = "/dev/ttys007"; profile.terminalWindowID = 123; profile.terminalProcessStarted = 42
        model.preferences.profiles = [profile]
        model.companions.terminalStarted = 42
        model.companions.windows = [TerminalWindow(windowID: 123, tty: "/dev/ttys007", title: "Ignored title", selected: true, front: true, agent: .claude)]
        model.rememberCompanionSessions()
        XCTAssertEqual(model.preferences.profiles[0].name, "Claude Code · 007")
        var session = ClaudeSession(id: "fixture-session", project: "/work/project-one", tty: "/dev/ttys007", processID: getpid(), processStarted: ClaudeProcess.startTime(getpid()))
        model.companions.sessions = [session]; model.rememberCompanionSessions()
        XCTAssertEqual(model.preferences.profiles[0].name, "Claude Code · project-one")
        XCTAssertEqual(model.preferences.profiles[0].terminalDisplayProject, "/work/project-one")
        XCTAssertEqual(model.preferences.profiles[0].projectPath, "/saved/launch-folder", "A display label cannot change the launch folder")
        XCTAssertEqual(model.preferences.profiles[0].terminalTTY, profile.terminalTTY)
        XCTAssertEqual(model.preferences.profiles[0].terminalProcessStarted, profile.terminalProcessStarted)
        session.project = "/work/project-two"; model.companions.sessions = [session]; model.rememberCompanionSessions()
        XCTAssertEqual(model.preferences.profiles[0].name, "Claude Code · project-two")
        XCTAssertEqual(model.preferences.profiles[0].projectPath, "/saved/launch-folder")
        XCTAssertEqual(DockModel(home: home).preferences.profiles[0].name, "Claude Code · project-two")
        model.preferences.profiles[0].name = "My custom terminal"
        session.project = "/work/project-three"; model.companions.sessions = [session]; model.rememberCompanionSessions()
        XCTAssertEqual(model.preferences.profiles[0].name, "My custom terminal")
    }

    func testSavedAndCustomNamesAreNotAutomatic() {
        var profile = Profile(id: "saved", name: "Claude Code · 007", color: "D7825A")
        profile.terminalAgent = .claude; profile.terminalTTY = "/dev/ttys007"
        XCTAssertFalse(TerminalProfileLabel.isAutomatic(profile, agent: .claude))
        profile.discoveredTerminal = true; profile.name = "Work terminal"
        XCTAssertFalse(TerminalProfileLabel.isAutomatic(profile, agent: .claude))
    }
}
