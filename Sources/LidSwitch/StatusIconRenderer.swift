import AppKit

enum StatusIconRenderer {
    static func image(keepsWorking: Bool?, forecastHours: Int?) -> NSImage {
        let text = forecastHours.map { String(min(999, max(0, $0))) }
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let isHalfClosed = keepsWorking == false
            let screenRect = isHalfClosed
                ? NSRect(x: 2.5, y: 4.5, width: 17, height: 7.5)
                : NSRect(x: 2.5, y: 4.5, width: 17, height: 12)
            let screen = NSBezierPath(
                roundedRect: screenRect,
                xRadius: isHalfClosed ? 1.5 : 2,
                yRadius: isHalfClosed ? 1.5 : 2
            )

            switch keepsWorking {
            case true: NSColor.systemGreen.setFill()
            case false: NSColor.systemYellow.setFill()
            case nil: NSColor.systemGray.setFill()
            }
            screen.fill()

            NSColor.labelColor.setStroke()
            screen.lineWidth = 1.35
            screen.stroke()

            let base = NSBezierPath()
            base.move(to: NSPoint(x: 1, y: 3.2))
            base.line(to: NSPoint(x: 21, y: 3.2))
            base.lineWidth = 1.7
            base.lineCapStyle = .round
            base.stroke()

            if let text {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: text.count <= 2 ? 8 : 6.5,
                        weight: .bold
                    ),
                    .foregroundColor: NSColor.black.withAlphaComponent(0.82),
                    .paragraphStyle: paragraph
                ]
                let textRect = NSRect(x: 3.5, y: 6.1, width: 15, height: 8.5)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: screenRect.insetBy(dx: 1, dy: 1), xRadius: 1, yRadius: 1).addClip()
                text.draw(in: textRect, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        // A template image would discard the green/yellow status fill.
        image.isTemplate = false
        return image
    }
}
