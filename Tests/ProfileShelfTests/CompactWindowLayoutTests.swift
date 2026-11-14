import AppKit
import XCTest
@testable import ProfileShelf

final class CompactWindowLayoutTests: XCTestCase {
    func testLargeDisplayCapsHeight() {
        let limits = CompactWindowLayout.limits(available: NSSize(width: 2560, height: 1440))
        XCTAssertEqual(limits.maximum.height, 640)
        XCTAssertEqual(limits.maximum.width, 520)
    }
    func testSmallDisplayFitsAndHasConsistentLimits() {
        let limits = CompactWindowLayout.limits(available: NSSize(width: 390, height: 480))
        XCTAssertEqual(limits.maximum.height, 384)
        XCTAssertLessThanOrEqual(limits.minimum.height, limits.maximum.height)
        XCTAssertLessThanOrEqual(limits.minimum.width, limits.maximum.width)
    }
}
