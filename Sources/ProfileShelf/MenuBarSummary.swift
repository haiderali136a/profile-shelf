import AppKit
import SwiftUI
import DockCore

extension AppDelegate {
    func trackedUsageProfiles() -> [Profile] {
        MenuBarProfileSelection.profiles(from: model.displayedProfiles, remembered: menuProfileIDs,
                                         running: Set(model.running.filter { !$0.value.isEmpty }.map(\.key)))
    }
    func rememberUsageProfile(_ id: String?) {
        guard let id, let profile = model.displayedProfiles.first(where: { $0.id == id }), profile.kind == .codex || profile.kind == .claude else { return }
        menuProfileIDs[profile.kind.rawValue] = id
        UserDefaults.standard.set(menuProfileIDs, forKey: "ProfileShelf.MenuProfiles")
        updateMenuBarSummary()
    }
    func updateMenuBarSummary() {
        guard let button = status?.button else { return }
        let profiles = trackedUsageProfiles()
        let lines = [ProfileProvider.codex, .claude].map { provider -> String in
            let prefix = provider == .codex ? "G" : "C"
            guard let profile = profiles.first(where: { $0.kind == provider }) else { return prefix + "  —" }
            return prefix + "  " + usage.menuQuota(profile).compact
        }
        let iconOnly = model.preferences.menuBarIconOnly == true
        button.attributedTitle = NSAttributedString(string: "")
        button.image = MenuBarSummaryArtwork.image(lines: lines, iconOnly: iconOnly)
        button.imagePosition = .imageOnly
        button.toolTip = profiles.map { profile in
            profile.kind.label + " · " + profile.name + "\n" + usage.menuQuota(profile).detail +
                (usage.entries[profile.id]?.error.map { "\n" + $0.message } ?? "")
        }.joined(separator: "\n\n") + "\n\nG: ChatGPT/Codex. C: Claude. Percentages used; short window then week. One remembered account per provider, not combined usage. Updates with normal usage refreshes (about 5 minutes in the background, 1 minute while the notch is open), subject to provider pauses. ~ means the reading is old; † means it came from a local tool. Click for accounts; right-click for the full menu."
        button.setAccessibilityLabel(iconOnly ? "Profile Shelf" : "Profile Shelf usage")
        button.setAccessibilityValue(iconOnly ? "" : profiles.map { $0.name + ": " + usage.menuQuota($0).compact }.joined(separator: "; "))
    }
    func quickPanel() -> some View {
        QuickSwitchPanel(model: model, usage: usage, activity: activity,
            choose: { [weak self] profile in
                self?.rememberUsageProfile(profile.id)
                self?.model.select(profile)
                if self?.model.switchingTargets[profile.kind] == nil { self?.quickPopover.performClose(nil) }
            }, alongside: { [weak self] profile in
                self?.rememberUsageProfile(profile.id)
                self?.model.select(profile, mode: .alongside)
                self?.quickPopover.performClose(nil)
            }, add: { [weak self] in self?.quickPopover.performClose(nil); self?.addProfile() },
            dashboard: { [weak self] in self?.quickPopover.performClose(nil); self?.showSettings() },
            insights: { [weak self] in
                self?.quickPopover.performClose(nil); self?.showSettings()
                DispatchQueue.main.async { NotificationCenter.default.post(name: .profileShelfShowInsights, object: nil) }
            }, tracked: { [weak self] profile in
                guard let self, self.status?.isVisible == true, self.model.preferences.menuBarIconOnly != true else { return false }
                return self.trackedUsageProfiles().contains(where: { $0.id == profile.id })
            })
    }
    func showQuickWindow() {
        quickPopover.performClose(nil)
        guard prepareCompactPresentation() else { return }
        if quickWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Profile Shelf"; window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: quickPanel().frame(maxWidth: .infinity, maxHeight: .infinity))
            host.sizingOptions = [] // Account details must scroll, never grow the window.
            window.contentView = host
            window.center(); window.setFrameAutosaveName("ProfileShelf.QuickWindow")
            quickWindow = window
        }
        if let window = quickWindow {
            let available = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
            let limits = CompactWindowLayout.limits(available: available)
            window.contentMinSize = limits.minimum
            window.contentMaxSize = limits.maximum
            let current = window.contentRect(forFrameRect: window.frame).size
            window.setContentSize(NSSize(width: min(max(current.width, limits.minimum.width), limits.maximum.width),
                                         height: min(max(current.height, limits.minimum.height), limits.maximum.height)))
            if window.isMiniaturized { window.deminiaturize(nil) }
        }
        NSApp.activate(ignoringOtherApps: true); quickWindow?.makeKeyAndOrderFront(nil)
    }
    func toggleQuickPanel() {
        guard let button = status?.button else { return }
        if quickPopover.isShown { quickPopover.performClose(nil); return }
        quickWindow?.orderOut(nil)
        guard prepareCompactPresentation() else { return }
        model.refresh()
        quickPopover.behavior = .transient
        let available = status?.button?.window?.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let size = CompactWindowLayout.limits(available: available).maximum
        let width = min(430, size.width), height = min(600, size.height)
        quickPopover.contentSize = NSSize(width: width, height: height)
        quickPopover.contentViewController = NSHostingController(rootView: quickPanel().frame(width: width, height: height))
        NSApp.activate(ignoringOtherApps: true)
        quickPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        quickPopover.contentViewController?.view.window?.makeKey()
        quickPopoverDismissal.start(popover: quickPopover, anchor: button)
    }
}
