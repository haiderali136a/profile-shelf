import AppKit
import XCTest
@testable import ProfileShelf

final class MenuBarArtworkTests: XCTestCase {
    @MainActor func testIconOnlyAndTwoLineSummaryFitAndRender() throws {
        let lines = ["G  5h 17%  7d 92%", "C  ~5h 1%  7d 95%"]
        let icon = MenuBarSummaryArtwork.image(lines: lines, iconOnly: true)
        let stats = MenuBarSummaryArtwork.image(lines: lines, iconOnly: false)
        XCTAssertEqual(icon.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(icon.isTemplate); XCTAssertTrue(stats.isTemplate)
        XCTAssertGreaterThan(stats.size.width, icon.size.width)
        XCTAssertLessThanOrEqual(stats.size.height, NSStatusBar.system.thickness + 2)
        guard let output = ProcessInfo.processInfo.environment["SHELF_RENDER_MENU"] else { return }
        let images = [stats, icon, MenuBarSummaryArtwork.image(lines: ["G  checking", "C  —"], iconOnly: false)]
        let canvas = NSImage(size: NSSize(width: 250, height: 96))
        canvas.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 250, height: 96).fill()
        for (row, image) in images.enumerated() {
            image.draw(in: NSRect(x: 12, y: 96 - CGFloat(row + 1) * 32 + (32 - image.size.height) / 2, width: image.size.width, height: image.size.height))
        }
        canvas.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(canvas.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
    }
}
