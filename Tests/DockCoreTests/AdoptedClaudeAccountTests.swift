import XCTest
@testable import DockCore

final class AdoptedClaudeAccountTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let adopted = "/Users/test/Library/Application Support/Older/Companions/profile-old"

    private func separate(_ id: String = "profile-new", adopted path: String? = nil) -> Profile {
        var profile = Profile(id: id, name: "Work", color: "C97B5D")
        profile.provider = .claude; profile.separateClaudeAccount = true; profile.adoptedHome = path
        return profile
    }

    func testAdoptedFolderOnlyAppliesToSeparateClaudeAccounts() {
        XCTAssertEqual(separate(adopted: adopted).home(in: home).path, adopted)
        // Without an adopted folder, a separate account keeps Profile Shelf's own folder.
        XCTAssertEqual(separate().home(in: home).path, "/Users/test/Library/Application Support/Profile Shelf/Companions/profile-new")
        // Every other kind of profile ignores the field.
        var shared = separate(adopted: adopted); shared.separateClaudeAccount = nil
        XCTAssertEqual(shared.home(in: home).path, "/Users/test/Library/Application Support/Profile Shelf/Companions/profile-new")
        var codex = Profile(id: "work", name: "Work", color: "377CF6"); codex.adoptedHome = adopted
        XCTAssertEqual(codex.home(in: home).path, "/Users/test/.codex-work")
        var agent = separate(adopted: adopted); agent.provider = .agent
        XCTAssertNotEqual(agent.home(in: home).path, adopted)
        // A relative value is never used as a path.
        XCTAssertEqual(separate(adopted: "relative/folder").home(in: home).path, "/Users/test/Library/Application Support/Profile Shelf/Companions/profile-new")
    }

    func testLaunchKeychainAndRunningWindowFollowTheAdoptedFolder() throws {
        let profile = separate(adopted: adopted)
        let arguments = try XCTUnwrap(ProfileLaunch.claudeArguments(profile: profile, home: home, application: URL(fileURLWithPath: "/Applications/Claude.app")))
        XCTAssertTrue(arguments.contains("CLAUDE_CONFIG_DIR=\(adopted)/claude-config"))
        XCTAssertTrue(arguments.contains("--user-data-dir=\(adopted)/electron-user-data"))
        // The Keychain item is derived from the exact config path, so the existing sign-in is reused.
        XCTAssertEqual(ClaudeCredentialService.name(configDirectory: profile.claudeConfigPath(in: home)),
                       ClaudeCredentialService.name(configDirectory: adopted + "/claude-config"))
        let running = ["/Applications/Claude.app/Contents/MacOS/Claude", "--user-data-dir=\(adopted)/electron-user-data"]
        XCTAssertEqual(ProcessIdentity.claudeProfileID(arguments: running, profiles: [profile], home: home), profile.id)
    }

    func testOnlyUnclaimedSeparateClaudeAccountsCanBeAdopted() {
        let claude = "/Applications/Claude.app/Contents/MacOS/Claude"
        let open = [claude, "--user-data-dir=\(adopted)/electron-user-data"]
        XCTAssertEqual(ProcessIdentity.adoptableClaudeHome(arguments: open, profiles: [], home: home)?.path, adopted)
        // Already a profile: not offered again.
        XCTAssertNil(ProcessIdentity.adoptableClaudeHome(arguments: open, profiles: [separate(adopted: adopted)], home: home))
        // The main sign-in, no user-data argument, an unexpected folder layout, a relative path or another app: never offered.
        XCTAssertNil(ProcessIdentity.adoptableClaudeHome(arguments: [claude], profiles: [], home: home))
        XCTAssertNil(ProcessIdentity.adoptableClaudeHome(arguments: [claude, "--user-data-dir=/Users/test/Library/Application Support/Claude"], profiles: [], home: home))
        XCTAssertNil(ProcessIdentity.adoptableClaudeHome(arguments: [claude, "--user-data-dir=/Users/test/Somewhere/else"], profiles: [], home: home))
        XCTAssertNil(ProcessIdentity.adoptableClaudeHome(arguments: [claude, "--user-data-dir=relative/electron-user-data"], profiles: [], home: home))
        XCTAssertNil(ProcessIdentity.adoptableClaudeHome(arguments: ["/Applications/Codex.app/Contents/MacOS/Codex", "--user-data-dir=\(adopted)/electron-user-data"], profiles: [], home: home))
    }

    func testSavedProfilesWithoutTheFieldStillDecode() throws {
        let data = Data(#"{"id":"profile-x","name":"Work","color":"C97B5D","provider":"claude","separateClaudeAccount":true}"#.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertNil(profile.adoptedHome)
        XCTAssertEqual(profile.home(in: home).path, "/Users/test/Library/Application Support/Profile Shelf/Companions/profile-x")
    }
}
