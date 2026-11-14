import CoreGraphics

/// The display properties that decide where the strip and panel live.
///
/// macOS posts a screen-parameters notification whenever the Dock resizes, which
/// happens each time an app launches or quits. The usable area is deliberately left
/// out, so those Dock-only changes refresh the layout instead of rebuilding (and
/// closing) an open panel.
public struct DisplayConfiguration: Equatable {
    public struct Display: Equatable {
        public let id: UInt32
        public let frame: CGRect
        public let notchHeight: CGFloat
        public let scale: CGFloat
        public init(id: UInt32, frame: CGRect, notchHeight: CGFloat, scale: CGFloat) {
            self.id = id; self.frame = frame; self.notchHeight = notchHeight; self.scale = scale
        }
    }

    public let displays: [Display]
    public init(_ displays: [Display]) { self.displays = displays }

    /// True when a display was added, removed, moved, resized, or changed notch or scale.
    public func needsRebuild(comparedTo previous: DisplayConfiguration?) -> Bool {
        guard let previous else { return true }
        return self != previous
    }
}
