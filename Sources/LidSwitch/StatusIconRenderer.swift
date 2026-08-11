import AppKit

enum StatusIconRenderer {
    static func image(forecastHours: Int?) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            NSColor.labelColor.setStroke()

            let screen = NSBezierPath(
                roundedRect: NSRect(x: 2.5, y: 4.5, width: 17, height: 12),
                xRadius: 2,
                yRadius: 2
            )
            screen.lineWidth = 1.5
            screen.stroke()

            let base = NSBezierPath()
            base.move(to: NSPoint(x: 1, y: 3.2))
            base.line(to: NSPoint(x: 21, y: 3.2))
            base.lineWidth = 1.7
            base.lineCapStyle = .round
            base.stroke()

            if let forecastHours {
                let text = String(min(999, max(0, forecastHours)))
                let fontSize: CGFloat = text.count <= 2 ? 8 : 6.5
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
                let textRect = NSRect(x: 3.5, y: 6.1, width: 15, height: 8.5)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: textRect).addClip()
                text.draw(in: textRect, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

