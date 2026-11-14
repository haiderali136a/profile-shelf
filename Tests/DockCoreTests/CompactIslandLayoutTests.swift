import XCTest
@testable import DockCore

final class CompactIslandLayoutTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    func testFullDefaultIsUnchangedAndCompactCanRevertExactly() {
        for scale in [0.85, 1, 1.3] {
            let original = IslandLayout(screen: screen, notchHeight: 32, notchWidth: 180, count: 4, scale: scale, hasMessage: false, terminalCount: 0)
            let full = IslandLayout(screen: screen, notchHeight: 32, notchWidth: 180, count: 4, scale: scale, hasMessage: false, terminalCount: 0, contentLayout: .full)
            let compact = IslandLayout(screen: screen, notchHeight: 32, notchWidth: 180, count: 4, scale: scale, hasMessage: false, terminalCount: 0, contentLayout: .compact)
            XCTAssertEqual(original, full)
            XCTAssertEqual(compact.collapsed, original.collapsed)
            XCTAssertEqual(compact.profileColumns, 4)
            XCTAssertLessThan(compact.expanded.width, full.expanded.width)
            XCTAssertLessThan(compact.expanded.height, full.expanded.height)
            if scale == 1 {
                XCTAssertEqual(full.expanded.width, 600)
                XCTAssertEqual(compact.expanded.width, 512)
                XCTAssertLessThanOrEqual(compact.expanded.width * compact.expanded.height, full.expanded.width * full.expanded.height * 0.66)
            }
        }
    }
    func testDetailsGrowDownwardWithoutChangingPagesOrOverflowingSmallScreens() {
        for placement in DockPlacement.allCases {
            for height in [640.0, 982] {
                let display = CGRect(x: 0, y: 0, width: 1024, height: height)
                let closed = IslandLayout(screen: display, notchHeight: 32, notchWidth: 180, count: 16, scale: 1, hasMessage: false, placement: placement, contentLayout: .compact)
                let opened = IslandLayout(screen: display, notchHeight: 32, notchWidth: 180, count: 16, scale: 1, hasMessage: false, placement: placement, contentLayout: .compact, showsCompactUsage: true)
                XCTAssertEqual(closed.profileRows, opened.profileRows)
                XCTAssertTrue(display.contains(opened.expanded))
                if placement == .topCenter { XCTAssertEqual(closed.expanded.maxY, opened.expanded.maxY) }
            }
        }
    }
}
