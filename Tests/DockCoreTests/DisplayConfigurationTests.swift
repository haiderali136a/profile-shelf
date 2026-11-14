import XCTest
import CoreGraphics
@testable import DockCore

final class DisplayConfigurationTests: XCTestCase {
    private let builtIn = DisplayConfiguration.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32, scale: 2)

    func testDockResizeFromAppLaunchOrQuitKeepsTheOpenPanel() {
        // Launching or quitting an app resizes the Dock: only the usable area changes,
        // which the configuration does not include, so the panel is not rebuilt.
        let before = DisplayConfiguration([builtIn])
        let afterDockResize = DisplayConfiguration([builtIn])
        XCTAssertFalse(afterDockResize.needsRebuild(comparedTo: before))
    }

    func testRealDisplayChangesRebuild() {
        let before = DisplayConfiguration([builtIn])
        let external = DisplayConfiguration.Display(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), notchHeight: 0, scale: 1)
        XCTAssertTrue(DisplayConfiguration([builtIn, external]).needsRebuild(comparedTo: before), "display added")
        XCTAssertTrue(DisplayConfiguration([]).needsRebuild(comparedTo: before), "display removed")
        let resized = DisplayConfiguration.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), notchHeight: 32, scale: 2)
        XCTAssertTrue(DisplayConfiguration([resized]).needsRebuild(comparedTo: before), "resolution changed")
        let scaled = DisplayConfiguration.Display(id: 1, frame: builtIn.frame, notchHeight: 32, scale: 1)
        XCTAssertTrue(DisplayConfiguration([scaled]).needsRebuild(comparedTo: before), "scale changed")
        let noNotch = DisplayConfiguration.Display(id: 1, frame: builtIn.frame, notchHeight: 0, scale: 2)
        XCTAssertTrue(DisplayConfiguration([noNotch]).needsRebuild(comparedTo: before), "notch inset changed")
    }

    func testFirstConfigurationAlwaysBuilds() {
        XCTAssertTrue(DisplayConfiguration([builtIn]).needsRebuild(comparedTo: nil))
    }
}
