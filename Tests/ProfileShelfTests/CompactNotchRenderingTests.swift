import AppKit
import SwiftUI
import XCTest
import DockCore
@testable import ProfileShelf

private actor CompactRenderUsage: UsageFetching {
    var paused = false
    func setPaused() { paused = true }
    func identity(for profile: Profile) async throws -> String { profile.id }
    func fetch(_ profile: Profile, expectedIdentity: String) async throws -> UsageSnapshot {
        if profile.id == "claude-personal" { throw UsageLoadError.claudeConnectionNeeded }
        if paused { throw UsageLoadError.rateLimited(Date().addingTimeInterval(300)) }
        let work = profile.name.contains("Work")
        return UsageSnapshot(identity: expectedIdentity, plan: "Fixture", windows: [
            UsageWindow(id: "week", duration: 604800, usedPercent: work ? 82 : 68, resetsAt: Date().addingTimeInterval(3 * 86400)),
            UsageWindow(id: "five", duration: 18000, usedPercent: work ? 14 : 68, resetsAt: Date().addingTimeInterval(3600))
        ], bankedResets: 2, applicableResets: 0, resetExpiries: [Date().addingTimeInterval(86400), Date().addingTimeInterval(172800)], fetchedAt: Date())
    }
}

final class CompactNotchRenderingTests: XCTestCase {
    @MainActor func testRenderCompactFullAndUsageStates() async throws {
        guard let path = ProcessInfo.processInfo.environment["SHELF_RENDER_COMPACT"] else { throw XCTSkip("Opt-in native compact renders") }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path), home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let fixture = CompactRenderUsage(), model = DockModel(home: home)
        let usage = UsageStore(client: fixture, claudeClient: fixture, claudeAccountClient: { _ in fixture }, home: home)
        let activity = ActivityMonitor(home: home), insights = InsightsStore()
        defer { usage.shutdown(); activity.shutdown(); insights.shutdown() }
        var first = Profile(id: "personal", name: "ChatGPT Personal", color: "377CF6")
        var second = Profile(id: "work", name: "ChatGPT Work", color: "377CF6"); second.dockIconStyle = .chatgpt
        var third = Profile(id: "claude-personal", name: "Claude Personal", color: "D7825A"); third.provider = .claude
        var fourth = Profile(id: "claude-work", name: "Claude Work", color: "D7825A"); fourth.provider = .claude; fourth.separateClaudeAccount = true
        first.dockIconText = "CP"
        model.preferences.profiles = [first, second, third, fourth]
        model.preferences.terminalsExpanded = false
        activity.entries[first.id] = ActivitySummary(working: 1, liveAvailable: true, appOpen: true)
        let running = try XCTUnwrap(RunningProfileApplication(NSRunningApplication.current))
        model.running[first.id] = [running]; model.running[fourth.id] = [running]
        usage.configure(model.preferences.profiles); usage.refreshAll()
        for _ in 0..<200 where usage.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(usage.entries[first.id]?.snapshot)
        for scale in [0.85, 1, 1.3] {
            model.preferences.scale = scale
            for mode in NotchLayout.allCases {
                model.preferences.notchLayout = mode
                let presentation = IslandPresentation(expanded: true)
                try await render(model, usage, activity, insights, presentation, to: directory.appendingPathComponent("\(mode.rawValue)-\(scale).png"))
            }
        }
        model.preferences.scale = 1; model.preferences.notchLayout = .compact
        let presentation = IslandPresentation(expanded: true)
        presentation.toggleCompactUsage(fourth.id)
        try await render(model, usage, activity, insights, presentation, to: directory.appendingPathComponent("compact-details.png"))
        presentation.toggleCompactResets()
        try await render(model, usage, activity, insights, presentation, to: directory.appendingPathComponent("compact-resets.png"))
        presentation.toggleCompactUsage(third.id)
        try await render(model, usage, activity, insights, presentation, to: directory.appendingPathComponent("compact-connect.png"))
        await fixture.setPaused(); usage.refresh(first, force: true)
        for _ in 0..<200 where usage.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
        presentation.toggleCompactUsage(first.id)
        try await render(model, usage, activity, insights, presentation, to: directory.appendingPathComponent("compact-paused.png"))
        model.preferences.profiles[0].name = "A deliberately long account name"
        model.preferences.profileGrid = ProfileGrid(columns: 2, rows: 2)
        presentation.closeCompactUsage()
        try await render(model, usage, activity, insights, presentation, to: directory.appendingPathComponent("compact-grid-long-name.png"))
    }

    @MainActor private func render(_ model: DockModel, _ usage: UsageStore, _ activity: ActivityMonitor, _ insights: InsightsStore, _ presentation: IslandPresentation, to url: URL) async throws {
        let layout = IslandLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32, notchWidth: 180, count: model.displayedProfiles.count, scale: model.preferences.scale, hasMessage: false, showsResetDetails: presentation.compactResetExpanded, terminalCount: 0, grid: model.preferences.profileGrid, contentLayout: model.preferences.effectiveNotchLayout, showsCompactUsage: presentation.compactUsageProfileID != nil)
        presentation.profileColumns = layout.profileColumns; presentation.profileRows = layout.profileRows
        let view = IslandView(model: model, usage: usage, activity: activity, insights: insights, presentation: presentation, notchHeight: 32, settings: {}, drag: { _, _ in }).background(.black)
        let host = NSHostingView(rootView: view.frame(width: layout.expanded.width, height: layout.expanded.height, alignment: .topLeading))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: layout.expanded.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.frame = CGRect(origin: .zero, size: layout.expanded.size)
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }
}
