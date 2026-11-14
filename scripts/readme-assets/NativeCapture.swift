import AppKit
import SwiftUI
import XCTest
import DockCore
@testable import ProfileShelf

private actor ReadmeUsageFixture: UsageFetching {
    func identity(for profile: Profile) async throws -> String { profile.id }
    func fetch(_ profile: Profile, expectedIdentity: String) async throws -> UsageSnapshot {
        let index = Int(profile.id.suffix(1)) ?? 0
        let short = [22.0, 59, 14, 31][index], week = [48.0, 67, 23, 42][index]
        return UsageSnapshot(identity: expectedIdentity, plan: "Sample", windows: [
            UsageWindow(id: "short", duration: 18000, usedPercent: short, resetsAt: Date().addingTimeInterval(Double([7200, 5400, 10800, 3600][index]))),
            UsageWindow(id: "week", duration: 604800, usedPercent: week, resetsAt: Date().addingTimeInterval(Double([259200, 345600, 432000, 172800][index])))
        ], bankedResets: 0, applicableResets: 0, resetExpiries: [], fetchedAt: Date())
    }
}

final class ReadmeAssetsRenderingTests: XCTestCase {
    @MainActor func testExportNativeViewsWithFictionalProfiles() async throws {
        guard let path = ProcessInfo.processInfo.environment["SHELF_README_MEDIA_DIR"] else { throw XCTSkip("Set SHELF_README_MEDIA_DIR for native README captures") }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readme-fixture-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home), activity = ActivityMonitor(home: home), insights = InsightsStore(), fixture = ReadmeUsageFixture()
        let usage = UsageStore(client: fixture, claudeClient: fixture, claudeAccountClient: { _ in fixture }, home: home)
        defer { usage.shutdown(); activity.shutdown(); insights.shutdown() }
        var profiles = [Profile(id: "readme-0", name: "ChatGPT Personal", color: "377CF6"), Profile(id: "readme-1", name: "ChatGPT Work", color: "377CF6"), Profile(id: "readme-2", name: "Claude Personal", color: "D7825A"), Profile(id: "readme-3", name: "Claude Work", color: "D7825A")]
        profiles[0].dockIconStyle = .initials
        profiles[0].dockIconText = "CP"
        profiles[1].dockIconStyle = .chatgpt
        profiles[2].provider = .claude; profiles[3].provider = .claude
        profiles[3].separateClaudeAccount = true
        for index in [1, 2, 3] { profiles[index].usesOriginalAppIcon = true }
        model.preferences.profiles = profiles
        model.preferences.showTerminalsSection = false
        model.preferences.showInsightsSection = true
        model.preferences.scale = 1
        model.activeProfile = profiles[0].id
        let running = try XCTUnwrap(RunningProfileApplication(NSRunningApplication.current))
        model.running[profiles[0].id] = [running]; model.running[profiles[3].id] = [running]
        usage.configure(profiles); usage.refreshAll()
        let deadline = Date().addingTimeInterval(4)
        while usage.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        for profile in profiles { XCTAssertNotNil(usage.entries[profile.id]?.snapshot, "Only fixture usage is used") }
        for scheme in [ColorScheme.dark, .light] {
            let theme = scheme == .dark ? "dark" : "light"
            for (mode, details, name) in [(NotchLayout.full, false, "full"), (.compact, false, "compact"), (.compact, true, "compact-details")] {
                model.preferences.notchLayout = mode
                let presentation = IslandPresentation(expanded: true)
                if details { presentation.toggleCompactUsage(profiles[3].id) }
                let layout = IslandLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 0, notchWidth: 180, count: profiles.count, scale: 1, hasMessage: false, showsInsightsSection: true, contentLayout: mode, showsCompactUsage: details)
                presentation.profileColumns = layout.profileColumns; presentation.profileRows = layout.profileRows
                let view = IslandView(model: model, usage: usage, activity: activity, insights: insights, presentation: presentation, notchHeight: 0, settings: {}, drag: { _, _ in }).background(.black)
                try await capture(view, size: layout.expanded.size, scheme: scheme, to: output.appendingPathComponent("\(name)-\(theme).png"))
                // A fixed canvas keeps the relative footprint visible in the native-view sequence.
                let sequence = view.frame(width: layout.expanded.width, height: layout.expanded.height).frame(width: 640, height: 544, alignment: .top).background(Color(nsColor: .windowBackgroundColor))
                try await capture(sequence, size: NSSize(width: 640, height: 544), scheme: scheme, to: output.appendingPathComponent("sequence-\(name)-\(theme).png"))
            }
            model.preferences.profiles = [profiles[0], profiles[3]]
            let quick = QuickSwitchPanel(model: model, usage: usage, activity: activity, choose: { _ in }, alongside: { _ in }, add: {}, dashboard: {}, insights: {}, tracked: { $0.id == profiles[0].id || $0.id == profiles[3].id })
            try await capture(quick, size: NSSize(width: 430, height: 500), scheme: scheme, to: output.appendingPathComponent("quick-\(theme).png"))
            model.preferences.profiles = profiles
            let artwork = MenuBarSummaryArtwork.image(lines: ["G  5h 22%  7d 48%", "C  5h 31%  7d 42%"], iconOnly: false)
            let menu = Image(nsImage: artwork).renderingMode(.template).foregroundStyle(Color.primary).frame(width: 224, height: 48).background(Color(nsColor: .windowBackgroundColor))
            try await capture(menu, size: NSSize(width: 224, height: 48), scheme: scheme, to: output.appendingPathComponent("menu-\(theme).png"))
        }
    }
    @MainActor func testExportDesktopAndTerminalExample() async throws {
        guard let path = ProcessInfo.processInfo.environment["SHELF_README_MEDIA_DIR"] else { throw XCTSkip("Set SHELF_README_MEDIA_DIR for native README captures") }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readme-terminal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = DockModel(home: home), activity = ActivityMonitor(home: home), insights = InsightsStore(), fixture = ReadmeUsageFixture()
        let usage = UsageStore(client: fixture, claudeClient: fixture, claudeAccountClient: { _ in fixture }, home: home)
        defer { usage.shutdown(); activity.shutdown(); insights.shutdown() }
        var profiles = [Profile(id: "readme-0", name: "ChatGPT Personal", color: "377CF6"), Profile(id: "readme-1", name: "ChatGPT Work", color: "377CF6"), Profile(id: "readme-2", name: "Claude Personal", color: "D7825A"), Profile(id: "readme-3", name: "Claude Work", color: "D7825A")]
        profiles[0].dockIconStyle = .initials; profiles[0].dockIconText = "CP"
        profiles[2].provider = .claude; profiles[3].provider = .claude
        profiles[3].separateClaudeAccount = true
        for index in [1, 2, 3] { profiles[index].usesOriginalAppIcon = true }
        var terminal = Profile(id: "readme-terminal", name: "Claude Code", color: "D7825A")
        terminal.provider = .claudeCode; terminal.terminalAgent = .claude
        terminal.usesOriginalAppIcon = true
        terminal.terminalTTY = "/dev/ttys007"; terminal.terminalWindowID = 7; terminal.terminalProcessStarted = 42
        terminal.terminalDisplayProject = home.appendingPathComponent("Website").path
        model.preferences.profiles = profiles + [terminal]
        model.preferences.notchLayout = .compact
        model.preferences.profileGrid = ProfileGrid(columns: 4, rows: 1)
        model.preferences.showTerminalsSection = true; model.preferences.terminalsExpanded = true
        model.preferences.showInsightsSection = true
        model.companions.terminalStarted = 42
        model.companions.windows = [TerminalWindow(windowID: 7, tty: "/dev/ttys007", title: "Website", selected: true, front: true, agent: .claude)]
        let running = try XCTUnwrap(RunningProfileApplication(NSRunningApplication.current))
        for profile in [profiles[0], profiles[3], terminal] { model.running[profile.id] = [running] }
        activity.entries[terminal.id] = ActivitySummary(unread: 0, working: 1, liveAvailable: true, appOpen: true)
        model.activeProfile = profiles[0].id
        usage.configure(profiles + [terminal]); usage.refreshAll()
        let deadline = Date().addingTimeInterval(4)
        while usage.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.liveTerminalProfiles.map(\.id), [terminal.id])
        XCTAssertNotNil(usage.entries[terminal.id]?.snapshot)
        let presentation = IslandPresentation(expanded: true)
        let layout = IslandLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 0, notchWidth: 180, count: 5, scale: 1, hasMessage: false, terminalCount: 1, grid: model.preferences.profileGrid, showsInsightsSection: true, contentLayout: .compact)
        presentation.profileColumns = layout.profileColumns; presentation.profileRows = layout.profileRows
        let view = IslandView(model: model, usage: usage, activity: activity, insights: insights, presentation: presentation, notchHeight: 0, settings: {}, drag: { _, _ in }).background(.black)
        try await capture(view, size: layout.expanded.size, scheme: .dark, to: output.appendingPathComponent("desktop-terminal.png"))
    }
    @MainActor private func capture<V: View>(_ view: V, size: NSSize, scheme: ColorScheme, to output: URL) async throws {
        let root = view.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme).environment(\.controlActiveState, .key)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting; hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(250)); hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        window.close()
    }
}
