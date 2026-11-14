import XCTest
@testable import DockCore

final class ProfileShelfBrandingTests: XCTestCase {
    func testRestoreOriginalKeepsLabelAndAccountButRemovesArtwork() {
        var value = Profile(id: "work", name: "Work", color: "377CF6", iconFilename: "picture.png")
        value.organizationBadgeFilename = "org.png"
        value.customDockLabel = "ChatGPT Company"
        value.dockIconText = "ORG"
        let originalHome = value.home(in: URL(fileURLWithPath: "/Users/test"))
        value.restoreOriginalAppIcon()
        XCTAssertEqual(value.usesOriginalAppIcon, true)
        XCTAssertNil(value.organizationBadgeFilename)
        XCTAssertNil(value.iconFilename)
        XCTAssertNil(value.dockIconText)
        XCTAssertEqual(value.dockDisplayName, "ChatGPT Company")
        XCTAssertEqual(value.home(in: URL(fileURLWithPath: "/Users/test")), originalHome)
    }
    func testShortcutTitleHasNoIdentitySuffixAndCannotEscapeParent() {
        var value = Profile(id: "unique123", name: "Work", color: "377CF6")
        value.customDockLabel = "ChatGPT Work"
        XCTAssertEqual(value.dockShortcutFilename, "ChatGPT Work.app")
        value.customDockLabel = "../../Work: A\nB"
        XCTAssertFalse(value.dockShortcutFilename.contains("/"))
        XCTAssertFalse(value.dockShortcutFilename.contains(":"))
        XCTAssertFalse(value.dockShortcutFilename.contains("\n"))
        XCTAssertTrue(value.dockShortcutFilename.hasSuffix(".app"))
    }
    func testOldProfileDecodesWithoutNewFields() throws {
        let data = Data(#"{"id":"work","name":"Work","color":"377CF6"}"#.utf8)
        let value = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertNil(value.organizationBadgeFilename)
        XCTAssertNil(value.customDockLabel)
        XCTAssertEqual(value.dockDisplayName, "ChatGPT Work")
    }
    func testChangingLabelAndBadgeDoesNotChangeAccountDirectory() {
        let home = URL(fileURLWithPath: "/Users/test")
        var value = Profile(id: "work", name: "Work", color: "377CF6")
        let before = value.home(in: home)
        value.customDockLabel = "ChatGPT Company"
        value.organizationBadgeFilename = "org.png"
        XCTAssertEqual(value.home(in: home), before)
        XCTAssertEqual(value.id, "work")
        XCTAssertEqual(value.dockDisplayName, "ChatGPT Company")
    }
    func testClaudeShortcutLabelDoesNotChangeItsAccountConfig() {
        let home = URL(fileURLWithPath: "/Users/test")
        var value = Profile(id: "company", name: "Work", color: "377CF6")
        value.provider = .claude; value.separateClaudeAccount = true
        let before = value.claudeConfigDirectory(in: home)
        XCTAssertEqual(value.dockDisplayName, "Claude Work")
        value.customDockLabel = "Claude My Organization"
        XCTAssertEqual(value.claudeConfigDirectory(in: home), before)
        XCTAssertEqual(value.dockDisplayName, "Claude My Organization")
    }
    func testBlankLabelKeepsDefaultAndNewMetadataRoundTrips() throws {
        var value = Profile(id: "work", name: "Work", color: "377CF6")
        value.customDockLabel = " \n "
        XCTAssertEqual(value.dockDisplayName, "ChatGPT Work")
        value.customDockLabel = "My Work"
        value.organizationBadgeFilename = "badge.png"
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(value)), value)
    }
}

extension ProfileShelfBrandingTests {
    func testDockLabelDoesNotRepeatTheAppName() {
        var chatgpt = Profile(id: "default", name: "ChatGPT", color: "377CF6")
        XCTAssertEqual(chatgpt.dockDisplayName, "ChatGPT")
        chatgpt.name = "ChatGPT Work"; XCTAssertEqual(chatgpt.dockDisplayName, "ChatGPT Work")
        chatgpt.name = "Work"; XCTAssertEqual(chatgpt.dockDisplayName, "ChatGPT Work")
        // Only a whole leading word counts, so similar names are left alone.
        chatgpt.name = "ChatGPTs"; XCTAssertEqual(chatgpt.dockDisplayName, "ChatGPT ChatGPTs")
        var claude = Profile(id: "profile-c", name: "Claude", color: "C97B5D"); claude.provider = .claude
        XCTAssertEqual(claude.dockDisplayName, "Claude")
        claude.name = "Claude Personal"; XCTAssertEqual(claude.dockDisplayName, "Claude Personal")
        claude.name = "Personal"; XCTAssertEqual(claude.dockDisplayName, "Claude Personal")
    }
}
