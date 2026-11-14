import AppKit
import SwiftUI
import XCTest
import DockCore
@testable import ProfileShelf

private actor RecoveryFixture: UsageFetching {
    var failure: UsageLoadError?
    func setFailure(_ value: UsageLoadError?) { failure = value }
    func identity(for profile: Profile) async throws -> String {
        if let failure { throw failure }
        return profile.id
    }
    func fetch(_ profile: Profile, expectedIdentity: String) async throws -> UsageSnapshot {
        UsageSnapshot(identity: expectedIdentity, plan: "Fixture", windows: [UsageWindow(id: "five", duration: 18000, usedPercent: 25, resetsAt: nil)], bankedResets: 0, applicableResets: 0, resetExpiries: [], fetchedAt: Date())
    }
}

final class QuickRecoveryRenderingTests: XCTestCase {
    @MainActor func testRefreshFirstWithAndWithoutRetainedReading() async throws {
        guard let output = ProcessInfo.processInfo.environment["SHELF_RENDER_RECOVERY"] else { throw XCTSkip("Opt-in native recovery renders") }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        for retained in [false, true] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let model = DockModel(home: home), fixture = RecoveryFixture(), activity = ActivityMonitor(home: home)
            let usage = UsageStore(client: fixture, claudeClient: fixture, home: home)
            defer { usage.shutdown(); activity.shutdown() }
            var profile = Profile(id: "fixture", name: "Claude Work", color: "D7825A"); profile.provider = .claude
            model.preferences.profiles = [profile]; usage.configure([profile])
            if retained {
                usage.refreshAll()
                try await settled(usage)
                XCTAssertNotNil(usage.entries[profile.id]?.snapshot)
            }
            await fixture.setFailure(.claudeTokenStale); usage.refresh(profile, force: true)
            try await settled(usage)
            XCTAssertEqual(usage.entries[profile.id]?.error, .claudeTokenStale)
            XCTAssertEqual(usage.entries[profile.id]?.snapshot != nil, retained)
            XCTAssertEqual(UsageRecoveryAction.actions(for: .claudeTokenStale), [.refresh, .reconnect])
            for width in [400.0, 430.0, 520.0] {
                let view = QuickSwitchPanel(model: model, usage: usage, activity: activity, choose: { _ in }, alongside: { _ in }, add: {}, dashboard: {}, insights: {}, tracked: { _ in false }).frame(width: width, height: 600).environment(\.colorScheme, .dark)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
                host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("recovery-\(retained)-\(Int(width)).png"))
                window.close()
            }
        }
    }
    @MainActor private func settled(_ usage: UsageStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while usage.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(usage.isRefreshing)
    }
}
