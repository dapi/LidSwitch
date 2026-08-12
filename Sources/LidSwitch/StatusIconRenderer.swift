import AppKit

enum StatusIconRenderer {
    static func image(keepsWorking: Bool?, forecastHours: Int?) -> NSImage {
        let text: String
        switch keepsWorking {
        case .some(true):
            text = forecastHours.map { String(min(999, max(0, $0))) } ?? "…"
        case .some(false):
            text = "Zz"
        case .none:
            text = "?"
        }
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let screenRect = NSRect(x: 2.5, y: 4.5, width: 17, height: 12)
            let screen = NSBezierPath(roundedRect: screenRect, xRadius: 2, yRadius: 2)

            switch keepsWorking {
            case .some(true): NSColor.systemGreen.setFill()
            case .some(false): NSColor.systemYellow.setFill()
            case .none: NSColor.systemGray.setFill()
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

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let fontSize: CGFloat
            if text == "Zz" {
                fontSize = 7.5
            } else if text.count <= 2 {
                fontSize = 8
            } else {
                fontSize = 6.5
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.black.withAlphaComponent(0.82),
                .paragraphStyle: paragraph
            ]
            let textRect = NSRect(x: 3.5, y: 6.1, width: 15, height: 8.5)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: screenRect.insetBy(dx: 1, dy: 1), xRadius: 1, yRadius: 1).addClip()
            text.draw(in: textRect, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        // A template image would discard the green/yellow status fill.
        image.isTemplate = false
        return image
    }
}
