import XCTest
import DockCore
@testable import ProfileShelf

extension CompanionIntegrationTests {
    @MainActor func testSeparateClaudeAccountIsAddedNextToTheSharedSignIn() throws {
        let model = DockModel(home: try temporaryHome())
        try model.createCompanion(kind: .claude, name: "Claude", project: nil, bundledHelper: nil)
        XCTAssertThrowsError(try model.createCompanion(kind: .claude, name: "Again", project: nil, bundledHelper: nil))
        try model.createCompanion(kind: .claude, name: "Work", project: nil, separateAccount: true, bundledHelper: nil)
        try model.createCompanion(kind: .claude, name: "Client", project: nil, separateAccount: true, bundledHelper: nil)
        let claude = model.preferences.profiles.filter { $0.kind == .claude }
        XCTAssertEqual(claude.map(\.usesSeparateClaudeAccount), [false, true, true])
        let shared = claude[0], work = claude[1], client = claude[2]
        for directory in [work.claudeConfigDirectory(in: model.home)!, work.claudeUserDataDirectory(in: model.home)!] {
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
            XCTAssertEqual(permissions, 0o700)
        }
        XCTAssertNotEqual(work.claudeUserDataDirectory(in: model.home), client.claudeUserDataDirectory(in: model.home))
        // Separate accounts read account usage from their own Claude Code sign-in, never the shared one.
        XCTAssertTrue(shared.usesClaudeAccountUsage)
        XCTAssertTrue(work.usesClaudeAccountUsage)
        let usage = UsageStore(home: model.home)
        XCTAssertEqual(usage.connectionKey(shared), "claude-account")
        XCTAssertEqual(Set([shared, work, client].map(usage.connectionKey)).count, 3)
        XCTAssertEqual(usage.claudeConfigPath(work), work.claudeConfigDirectory(in: model.home)?.path)
        XCTAssertEqual(model.claudeBridges.map(\.settings), [model.home.appendingPathComponent(".claude/settings.json"),
            work.claudeConfigDirectory(in: model.home)!.appendingPathComponent("settings.json"), client.claudeConfigDirectory(in: model.home)!.appendingPathComponent("settings.json")])
        XCTAssertTrue(try model.recognizeClaudeDesktop(application: nil) == false)

        var sharedSession = ClaudeSession(id: "shared", project: "/project")
        sharedSession.state = .working
        var workSession = ClaudeSession(id: "work", project: "/project")
        workSession.configDirectory = work.claudeConfigDirectory(in: model.home)!.standardizedFileURL.path
        var terminalSession = ClaudeSession(id: "terminal", project: "/project", tty: "/dev/ttys004")
        terminalSession.configDirectory = workSession.configDirectory
        model.companions.sessions = [sharedSession, workSession, terminalSession]
        XCTAssertEqual(model.companions.sessions(for: shared).map(\.id), ["shared"])
        XCTAssertEqual(model.companions.sessions(for: work).map(\.id), ["work"])
        XCTAssertEqual(model.companions.sessions(for: client).map(\.id), [])
        XCTAssertEqual(DockModel(home: model.home).preferences.profiles.filter(\.usesSeparateClaudeAccount).map(\.id), [work.id, client.id])
    }

    func testSeparateAccountBridgeWritesOnlyItsOwnSettings() throws {
        let home = try temporaryHome(), config = home.appendingPathComponent("Library/Application Support/Profile Shelf/Companions/work/claude-config")
        let shared = ClaudeBridge(home: home), separate = ClaudeBridge(home: home, configDirectory: config)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try Data(#"{"statusLine":{"type":"command","command":"printf work"}}"#.utf8).write(to: separate.settings)
        let helper = home.appendingPathComponent("fixture-helper")
        try Data("fixture executable".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try separate.setEnabled(true, bundledHelper: helper)
        XCTAssertTrue(separate.enabled)
        XCTAssertFalse(shared.enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.settings.path))
        XCTAssertNotEqual(separate.originalStatusline, shared.originalStatusline)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: separate.originalStatusline)) as? [String: Any]
        XCTAssertEqual(saved?["command"] as? String, "printf work")
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.originalStatusline.path))
        try separate.setEnabled(false, bundledHelper: nil)
        XCTAssertFalse(separate.enabled)
    }
}

extension CompanionIntegrationTests {
    @MainActor func testAdoptingAnExistingSeparateClaudeAccountKeepsItsFolderSafe() throws {
        let model = DockModel(home: try temporaryHome())
        let fm = FileManager.default
        let folder = model.home.appendingPathComponent("Library/Application Support/Older/Companions/profile-old")
        try fm.createDirectory(at: folder.appendingPathComponent("claude-config"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("electron-user-data"), withIntermediateDirectories: true)
        try Data("history".utf8).write(to: folder.appendingPathComponent("claude-config/history.jsonl"))

        try model.adoptClaudeAccount(folder: folder, name: "Work", bundledHelper: nil)
        let profile = try XCTUnwrap(model.preferences.profiles.first { $0.adoptedHome != nil })
        XCTAssertTrue(profile.usesSeparateClaudeAccount)
        XCTAssertEqual(profile.home(in: model.home).standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(profile.claudeConfigDirectory(in: model.home)?.standardizedFileURL, folder.appendingPathComponent("claude-config").standardizedFileURL)
        // Nothing is created in Profile Shelf's own folder for an adopted account.
        XCTAssertFalse(fm.fileExists(atPath: model.home.appendingPathComponent("Library/Application Support/Profile Shelf/Companions/\(profile.id)").path))

        // The same account cannot be added twice.
        XCTAssertThrowsError(try model.adoptClaudeAccount(folder: folder, name: "Again", bundledHelper: nil))
        // A folder without a Claude Code configuration, or a symbolic link, is refused.
        let empty = model.home.appendingPathComponent("empty"); try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try model.adoptClaudeAccount(folder: empty, name: "Empty", bundledHelper: nil))
        let link = model.home.appendingPathComponent("link"); try fm.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertThrowsError(try model.adoptClaudeAccount(folder: link, name: "Link", bundledHelper: nil))

        // Removing the profile never moves the adopted folder to the Trash, even if asked to.
        XCTAssertThrowsError(try model.removeProfile(profile, trashData: true))
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("claude-config/history.jsonl").path))
        try model.removeProfile(profile, trashData: false)
        XCTAssertFalse(model.preferences.profiles.contains { $0.id == profile.id })
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("claude-config/history.jsonl").path))
    }
}

extension CompanionIntegrationTests {
    @MainActor func testOpenSeparateClaudeAccountIsAddedAutomaticallyOnceAndNotAfterRemoval() async throws {
        let model = DockModel(home: try temporaryHome())
        let folder = model.home.appendingPathComponent("Library/Application Support/Older/Companions/profile-old")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("claude-config"), withIntermediateDirectories: true)
        func settle() async { for _ in 0..<5 { await Task.yield(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } }

        model.adoptOpenClaudeAccounts(folders: [folder]); await settle()
        let added = model.preferences.profiles.filter { $0.adoptedHome != nil }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.addedAutomatically, true)
        XCTAssertEqual(added.first?.name, "Claude")
        // A second detection of the same open account adds nothing.
        model.adoptOpenClaudeAccounts(folders: [folder]); await settle()
        XCTAssertEqual(model.preferences.profiles.filter { $0.adoptedHome != nil }.count, 1)
        // Once removed, it is not added again automatically, and its folder stays.
        try model.removeProfile(try XCTUnwrap(added.first), trashData: false)
        model.adoptOpenClaudeAccounts(folders: [folder]); await settle()
        XCTAssertTrue(model.preferences.profiles.filter { $0.adoptedHome != nil }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("claude-config").path))
    }
}

extension CompanionIntegrationTests {
    @MainActor func testSignInHintOnlyOnFirstLaunchWhileAnotherClaudeIsOpen() throws {
        let home = try temporaryHome(), fm = FileManager.default
        let missing = home.appendingPathComponent("missing/electron-user-data")
        let empty = home.appendingPathComponent("empty/electron-user-data")
        let used = home.appendingPathComponent("used/electron-user-data")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try fm.createDirectory(at: used, withIntermediateDirectories: true)
        try Data().write(to: empty.appendingPathComponent(".DS_Store"))
        try Data("{}".utf8).write(to: used.appendingPathComponent("Local State"))
        // First launch with another Claude open: the hint names the account.
        XCTAssertEqual(DockModel.claudeSignInHint(name: "Claude Work", userData: missing, otherClaudeRunning: true)?.hasPrefix("Sign in to Claude Work"), true)
        XCTAssertNotNil(DockModel.claudeSignInHint(name: "Claude Work", userData: empty, otherClaudeRunning: true), "hidden files do not count as app data")
        // Already used, or nothing else open: no hint.
        XCTAssertNil(DockModel.claudeSignInHint(name: "Claude Work", userData: used, otherClaudeRunning: true))
        XCTAssertNil(DockModel.claudeSignInHint(name: "Claude Work", userData: missing, otherClaudeRunning: false))
    }
}

extension CompanionIntegrationTests {
    func testInheritedClaudeConfigurationIsDroppedBeforeOpeningAnyClaude() {
        let previous = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        defer { if let previous { setenv("CLAUDE_CONFIG_DIR", previous, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") } }
        setenv("CLAUDE_CONFIG_DIR", "/Users/test/Library/Application Support/Other/claude-config", 1)
        setenv("PATH_FIXTURE_KEEP", "kept", 1); defer { unsetenv("PATH_FIXTURE_KEEP") }
        ProfileShelf.dropInheritedClaudeConfiguration()
        XCTAssertNil(ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"])
        // Nothing else is removed.
        XCTAssertEqual(ProcessInfo.processInfo.environment["PATH_FIXTURE_KEEP"], "kept")
        // Safe when the variable is not set at all, as when opened from Finder.
        ProfileShelf.dropInheritedClaudeConfiguration()
        XCTAssertNil(ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"])
    }
}
