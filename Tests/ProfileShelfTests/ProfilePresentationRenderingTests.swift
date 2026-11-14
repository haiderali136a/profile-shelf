import AppKit
import SwiftUI
import XCTest
import DockCore
@testable import ProfileShelf

private actor AuditUsageFixture: UsageFetching {
    func identity(for profile: Profile) async throws -> String {
        if profile.id == "audit-stale" { throw UsageLoadError.claudeTokenStale }
        return profile.id
    }
    func fetch(_ profile: Profile, expectedIdentity: String) async throws -> UsageSnapshot {
        UsageSnapshot(identity: expectedIdentity, plan: "Fixture", windows: [
            UsageWindow(id: "short", duration: 18000, usedPercent: 25, resetsAt: Date().addingTimeInterval(3600)),
            UsageWindow(id: "week", duration: 604800, usedPercent: 45, resetsAt: Date().addingTimeInterval(86400))
        ], bankedResets: 0, applicableResets: 0, resetExpiries: [], fetchedAt: Date())
    }
}

final class ProfilePresentationRenderingTests: XCTestCase {
    @MainActor func testRenderExistingAgentInQuickWindow() async throws {
        guard let renderPath = ProcessInfo.processInfo.environment["SHELF_RENDER_PRESENTATION"] else { throw XCTSkip("Opt-in native presentation renders") }
        try FileManager.default.createDirectory(atPath: renderPath, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home), activity = ActivityMonitor(home: home), fixture = AuditUsageFixture()
        let usage = UsageStore(client: fixture, claudeClient: fixture, home: home)
        defer { usage.shutdown(); activity.shutdown() }
        var profile = Profile(id: "audit-antigravity", name: "Antigravity", color: "377CF6")
        profile.provider = .agent; profile.agentID = "antigravity"
        model.preferences.profiles = [profile]
        XCTAssertEqual(model.displayedProfiles.map(\.id), [profile.id])
        let view = QuickSwitchPanel(model: model, usage: usage, activity: activity, choose: { _ in }, alongside: { _ in }, add: {}, dashboard: {}, insights: {}, tracked: { _ in false })
            .frame(width: 430, height: 430).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 430, height: 430), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(x: 0, y: 0, width: 430, height: 430)
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: renderPath).appendingPathComponent("agent-only-quick-window.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        window.close()
    }
    @MainActor func testRenderFullAndCompactActivityAndExpiredToken() async throws {
        guard let renderPath = ProcessInfo.processInfo.environment["SHELF_RENDER_PRESENTATION"] else { throw XCTSkip("Opt-in native presentation renders") }
        try FileManager.default.createDirectory(atPath: renderPath, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: renderPath)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home), activity = ActivityMonitor(home: home), fixture = AuditUsageFixture()
        let usage = UsageStore(client: fixture, claudeClient: fixture, home: home), insights = InsightsStore()
        defer { usage.shutdown(); activity.shutdown(); insights.shutdown() }
        var profiles = [
            Profile(id: "audit-offline", name: "Activity Offline", color: "377CF6"),
            Profile(id: "audit-unread", name: "Unread + Working", color: "377CF6"),
            Profile(id: "audit-waiting", name: "Working + Waiting", color: "377CF6"),
            Profile(id: "audit-stale", name: "Expired Claude", color: "D7825A")
        ]
        profiles[3].provider = .claude
        model.preferences.profiles = profiles
        model.preferences.showTerminalsSection = false; model.preferences.showInsightsSection = false
        let running = try XCTUnwrap(RunningProfileApplication(NSRunningApplication.current))
        for p in profiles { model.running[p.id] = [running] }
        activity.entries[profiles[0].id] = ActivitySummary(unread: nil, liveAvailable: false, appOpen: true, connectionIssue: .metadata)
        activity.entries[profiles[1].id] = ActivitySummary(unread: 3, working: 1, liveAvailable: true, appOpen: true)
        activity.entries[profiles[2].id] = ActivitySummary(unread: 0, working: 2, waiting: 1, liveAvailable: true, appOpen: true)
        usage.configure(profiles); usage.refreshAll()
        let deadline = Date().addingTimeInterval(3)
        while usage.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(usage.entries[profiles[3].id]?.error, .claudeTokenStale)
        XCTAssertNotNil(usage.entries[profiles[0].id]?.snapshot)
        for scale in [0.85, 1.0, 1.3] {
        model.preferences.scale = scale
        for mode in NotchLayout.allCases {
            model.preferences.notchLayout = mode
            let presentation = IslandPresentation(expanded: true)
            if mode == .compact { presentation.toggleCompactUsage(profiles[3].id) }
            let layout = IslandLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 0, notchWidth: 180, count: profiles.count, scale: scale, hasMessage: false, showsInsightsSection: false, contentLayout: mode, showsCompactUsage: mode == .compact)
            presentation.profileColumns = layout.profileColumns; presentation.profileRows = layout.profileRows
            let view = IslandView(model: model, usage: usage, activity: activity, insights: insights, presentation: presentation, notchHeight: 0, settings: {}, drag: { _, _ in }).background(.black)
            let host = NSHostingView(rootView: view.frame(width: layout.expanded.width, height: layout.expanded.height, alignment: .topLeading))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: layout.expanded.size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(origin: .zero, size: layout.expanded.size)
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(mode.rawValue + (scale == 1 ? "" : "-\(scale)") + ".png"))
            window.close()
        }
        }
    }
}
