import AppKit
import XCTest
@testable import ProfileShelf

@MainActor private final class MenuBarTestTarget: NSObject {
    @objc func clicked() {}
}

final class MenuBarInteractionTests: XCTestCase {
    @MainActor func testAccessModesRemoveAndRecreateConfiguredItems() throws {
        _ = NSApplication.shared
        let subject = MenuBarStatusItem(), target = MenuBarTestTarget()
        defer { subject.shutdown() }
        var prefs = Preferences(), previous: NSStatusItem?, configurations = 0
        for mode in ["both", "notch", "both", "notch", "menu", "both"] {
            prefs.showNotch = mode != "menu"; prefs.showMenuBarIcon = mode != "notch"
            subject.setVisible(AppVisibility.menuBarVisible(preferences: prefs)) { item in
                configurations += 1
                item.button?.image = BrandArtwork.template(size: 16)
                item.button?.target = target; item.button?.action = #selector(MenuBarTestTarget.clicked)
            }
            if mode == "notch" {
                XCTAssertNil(subject.item)
            } else {
                let item = try XCTUnwrap(subject.item)
                XCTAssertTrue(item.isVisible)
                XCTAssertNotNil(item.button?.image)
                XCTAssertTrue(item.button?.target === target)
                XCTAssertEqual(item.button?.action, #selector(MenuBarTestTarget.clicked))
                if mode != "both" || configurations < 3 { XCTAssertFalse(item === previous) }
                previous = item
            }
        }
        XCTAssertEqual(configurations, 3, "An already-visible item must not be recreated on every preference change")
        prefs.showNotch = false; prefs.showMenuBarIcon = false
        XCTAssertTrue(AppVisibility.menuBarVisible(preferences: prefs), "Malformed settings retain an access route")
    }

    @MainActor func testOutsideClickRegionsPreservePopoverAndAnchorClicks() {
        let body = NSRect(x: 100, y: 100, width: 300, height: 400), anchor = NSRect(x: 200, y: 510, width: 40, height: 24)
        XCTAssertFalse(MenuBarPopoverDismissal.shouldClose(point: NSPoint(x: 150, y: 150), popoverFrame: body, anchorFrame: anchor, menuTracking: false))
        XCTAssertFalse(MenuBarPopoverDismissal.shouldClose(point: NSPoint(x: 210, y: 520), popoverFrame: body, anchorFrame: anchor, menuTracking: false), "The status button retains its own toggle action")
        XCTAssertTrue(MenuBarPopoverDismissal.shouldClose(point: NSPoint(x: 500, y: 300), popoverFrame: body, anchorFrame: anchor, menuTracking: false))
        XCTAssertFalse(MenuBarPopoverDismissal.shouldClose(point: NSPoint(x: 500, y: 300), popoverFrame: body, anchorFrame: anchor, menuTracking: true), "Nested account menus must remain usable")
    }

    @MainActor func testNativePopoverDismissesAndReleasesMonitors() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 30, height: 20))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)); content.addSubview(anchor); window.contentView = content
        let popover = NSPopover(), subject = MenuBarPopoverDismissal()
        defer { subject.stop(); popover.close(); window.close() }
        popover.animates = false; popover.behavior = .applicationDefined
        let controller = NSViewController(); controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)); popover.contentViewController = controller
        window.orderFront(nil)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        subject.start(popover: popover, anchor: anchor)
        XCTAssertTrue(popover.isShown); XCTAssertTrue(subject.monitoring)
        let frame = try XCTUnwrap(popover.contentViewController?.view.window?.frame)
        subject.handleClick(at: NSPoint(x: frame.midX, y: frame.midY))
        XCTAssertTrue(popover.isShown)
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        subject.handleClick(at: NSPoint(x: -10000, y: -10000))
        XCTAssertTrue(popover.isShown)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        subject.handleClick(at: NSPoint(x: -10000, y: -10000))
        XCTAssertFalse(popover.isShown); XCTAssertFalse(subject.monitoring)
        subject.stop()
        XCTAssertFalse(subject.monitoring)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        subject.start(popover: popover, anchor: anchor)
        XCTAssertTrue(popover.isShown)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(popover.isShown)
        XCTAssertFalse(subject.monitoring, "Changing to another app releases both monitors")
    }
}
