import AppKit
import SwiftUI

/// Three profile cards on a shelf. A template image follows the menu bar's contrast.
enum BrandArtwork {
    static func template(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform(); transform.scale(by: rect.width / 64); transform.concat()
            let mark = NSBezierPath(); mark.windingRule = .evenOdd
            for x in [10, 26, 42] {
                mark.append(NSBezierPath(roundedRect: NSRect(x: x, y: 20, width: 12, height: 32), xRadius: 4, yRadius: 4))
                mark.appendOval(in: NSRect(x: x+3, y: 38, width: 6, height: 6))
                mark.append(NSBezierPath(roundedRect: NSRect(x: x+3, y: 31, width: 6, height: 2), xRadius: 1, yRadius: 1))
            }
            mark.append(NSBezierPath(roundedRect: NSRect(x: 6, y: 10, width: 52, height: 4), xRadius: 2, yRadius: 2))
            NSColor.black.setFill(); mark.fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Profile Shelf"
        return image
    }
}

struct BrandMark: View {
    var size: CGFloat = 18
    var body: some View {
        Image(nsImage: BrandArtwork.template(size: size)).renderingMode(.template)
            .resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityLabel("Profile Shelf")
    }
}

/// A single template image gives the mark and both text lines one shared vertical center.
/// Keep positioning independent of AppKit's separate multiline-title layout.
enum MenuBarSummaryArtwork {
    static func image(lines: [String], iconOnly: Bool) -> NSImage {
        guard !iconOnly else { return BrandArtwork.template(size: 16) }
        let style = NSMutableParagraphStyle(); style.lineSpacing = 0; style.alignment = .left
        let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.black, .paragraphStyle: style
        ])
        let size = text.size(), height = max(16, ceil(size.height)), width = 20 + ceil(size.width)
        let mark = BrandArtwork.template(size: 16)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            mark.draw(in: NSRect(x: 0, y: (height - 16) / 2, width: 16, height: 16))
            text.draw(in: NSRect(x: 20, y: (height - size.height) / 2, width: ceil(size.width), height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
