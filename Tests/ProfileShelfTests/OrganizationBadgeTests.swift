import AppKit
import XCTest
import DockCore
@testable import ProfileShelf

final class OrganizationBadgeTests: XCTestCase {
    @MainActor func testBadgePreservesTheOfficialBaseAndOnlyChangesItsCorner() throws {
        let vendor = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let badge = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        var profile = Profile(id: "work", name: "Work", color: "00FF00")
        profile.dockIconStyle = .dot
        let image = NativeProfileArtwork.preview(profile: profile, image: nil, vendor: vendor, size: 100, organization: badge)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        image.draw(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        NSGraphicsContext.restoreGraphicsState()
        let center = try XCTUnwrap(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.blueComponent, 0.9)
        XCTAssertLessThan(center.redComponent, 0.1)
        // Bitmap origin can depend on the representation: the badge must occur
        // on exactly one of these vertical mirror points, not at the app center.
        let corners = try [20, 80].map { y in try XCTUnwrap(bitmap.colorAt(x: 79, y: y)?.usingColorSpace(.deviceRGB)) }
        XCTAssertEqual(corners.filter { $0.redComponent > 0.9 && $0.blueComponent < 0.1 }.count, 1)
    }
}
