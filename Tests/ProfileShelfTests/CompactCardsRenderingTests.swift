import AppKit
import SwiftUI
import XCTest
import DockCore
@testable import ProfileShelf

private actor CompactCardUsageFixture: UsageFetching {
    func identity(for profile: Profile) async throws -> String { profile.id }
    func fetch(_ profile: Profile, expectedIdentity: String) async throws -> UsageSnapshot {
        UsageSnapshot(identity: expectedIdentity, plan: "Fixture", windows: [
            UsageWindow(id: "short", duration: 18000, usedPercent: 35, resetsAt: Date().addingTimeInterval(3600)),
            UsageWindow(id: "week", duration: 604800, usedPercent: 62, resetsAt: Date().addingTimeInterval(86400))
        ], bankedResets: nil, applicableResets: nil, resetExpiries: nil, fetchedAt: Date())
    }
}

final class CompactCardsRenderingTests: XCTestCase {
    @MainActor func testCompactCardsStayInsideBoundedWindowAtSupportedWidths() async throws {
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home), activity = ActivityMonitor(home: home)
        let fixture = CompactCardUsageFixture()
        let usage = UsageStore(client: fixture, claudeClient: fixture, home: home)
        defer { usage.shutdown(); activity.shutdown() }
        var profiles = [Profile(id: "personal", name: "ChatGPT Personal", color: "377CF6"), Profile(id: "work", name: "ChatGPT Work", color: "377CF6"), Profile(id: "claude-personal", name: "Claude Personal", color: "377CF6"), Profile(id: "claude-work", name: "Claude Work", color: "377CF6")]
        profiles[2].provider = .claude; profiles[3].provider = .claude
        model.preferences.profiles = profiles
        usage.configure(profiles); usage.refreshAll()
        let deadline = Date().addingTimeInterval(3)
        while usage.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(profiles.compactMap { usage.menuSnapshot($0).snapshot }.count, 4)
        for width in [400.0, 430.0] {
            for scheme in [ColorScheme.dark, .light] {
                let view = QuickSwitchPanel(model: model, usage: usage, activity: activity, choose: { _ in }, alongside: { _ in }, add: {}, dashboard: {}, insights: {}, tracked: { _ in false })
                    .frame(width: width, height: 600).environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                host.sizingOptions = []
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, 600)
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                if let output = ProcessInfo.processInfo.environment["SHELF_RENDER_COMPACT"] {
                    let folder = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("compact-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                }
                window.close()
            }
        }
    }
}
