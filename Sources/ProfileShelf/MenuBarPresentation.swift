import AppKit
import Combine

/// Remove hidden items and create/configure a fresh item when quick access returns.
@MainActor final class MenuBarStatusItem {
    private(set) var item: NSStatusItem?
    @discardableResult func setVisible(_ visible: Bool, configure: (NSStatusItem) -> Void) -> Bool {
        guard visible else { shutdown(); return false }
        guard item == nil else { return false }
        let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = created
        configure(created)
        created.isVisible = true
        return true
    }
    func shutdown() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }
}

/// Click monitors exist only while this popover is open and never consume clicks.
@MainActor final class MenuBarPopoverDismissal: NSObject, NSPopoverDelegate {
    private weak var popover: NSPopover?
    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var trackedMenus = Set<ObjectIdentifier>()
    var monitoring: Bool { localMonitor != nil || globalMonitor != nil || !subscriptions.isEmpty }

    func start(popover: NSPopover, anchor: NSView) {
        stop()
        self.popover = popover; self.anchor = anchor; popover.delegate = self
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfOutside() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside() }
            return event
        }
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification, object: NSApp)
            .sink { [weak self] _ in self?.popover?.performClose(nil) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] notice in
                if let menu = notice.object as? NSMenu { self?.trackedMenus.insert(ObjectIdentifier(menu)) }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] notice in
                if let menu = notice.object as? NSMenu { self?.trackedMenus.remove(ObjectIdentifier(menu)) }
            }.store(in: &subscriptions)
    }
    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        subscriptions.removeAll(); trackedMenus.removeAll()
        popover = nil; anchor = nil
    }
    func popoverDidClose(_ notification: Notification) { stop() }

    static func shouldClose(point: NSPoint, popoverFrame: NSRect, anchorFrame: NSRect, menuTracking: Bool) -> Bool {
        !menuTracking && !popoverFrame.contains(point) && !anchorFrame.contains(point)
    }
    private func closeIfOutside() { handleClick(at: NSEvent.mouseLocation) }
    func handleClick(at point: NSPoint) {
        guard let popover, popover.isShown else { stop(); return }
        let popoverFrame = popover.contentViewController?.view.window?.frame ?? .zero
        let anchorFrame = anchor.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } } ?? .zero
        if Self.shouldClose(point: point, popoverFrame: popoverFrame, anchorFrame: anchorFrame, menuTracking: !trackedMenus.isEmpty) {
            popover.performClose(nil)
        }
    }
}
