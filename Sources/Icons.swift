import Cocoa

struct LightningIcon {
    static func menuBarImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 10.8, y: 17.0))
        path.line(to: NSPoint(x: 3.8, y: 8.9))
        path.line(to: NSPoint(x: 8.2, y: 8.9))
        path.line(to: NSPoint(x: 6.9, y: 1.0))
        path.line(to: NSPoint(x: 14.4, y: 10.2))
        path.line(to: NSPoint(x: 9.8, y: 10.2))
        path.close()
        color.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

struct WaveIcon {
    static func menuBarImage(color: NSColor, phase: CGFloat) -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.2
        let mid = size.height / 2
        for x in stride(from: CGFloat(1), through: size.width - 1, by: 1) {
            let y = mid + sin((x / 3.0) + phase) * 5.0
            if x == 1 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.stroke()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

struct MouseIcon {
    static func menuBarImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        color.setStroke()
        color.setFill()

        let body = NSBezierPath(roundedRect: NSRect(x: 4.0, y: 1.5, width: 10.0, height: 15.0), xRadius: 5.0, yRadius: 5.0)
        body.lineWidth = 1.8
        body.stroke()

        let buttonSplit = NSBezierPath()
        buttonSplit.lineWidth = 1.4
        buttonSplit.move(to: NSPoint(x: 4.8, y: 11.1))
        buttonSplit.line(to: NSPoint(x: 13.2, y: 11.1))
        buttonSplit.stroke()

        let centerSplit = NSBezierPath()
        centerSplit.lineWidth = 1.4
        centerSplit.move(to: NSPoint(x: 9.0, y: 16.0))
        centerSplit.line(to: NSPoint(x: 9.0, y: 11.1))
        centerSplit.stroke()

        let wheel = NSBezierPath(roundedRect: NSRect(x: 8.25, y: 12.4, width: 1.5, height: 2.4), xRadius: 0.75, yRadius: 0.75)
        wheel.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
