import AppKit

/// Menu-bar glyph matching the app icon: a keycap on its stem with sound waves.
/// Drawn in code as a template image so macOS tints it for light/dark menu bars.
enum MenuBarIcon {
    static let on = make(active: true)
    static let off = make(active: false)

    private static func make(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Keycap: a trapezoid, wider at the base.
            let cap = NSBezierPath()
            cap.move(to: NSPoint(x: 1.5, y: 5.5))
            cap.line(to: NSPoint(x: 13.5, y: 5.5))
            cap.line(to: NSPoint(x: 11.3, y: 13.5))
            cap.line(to: NSPoint(x: 3.7, y: 13.5))
            cap.close()
            cap.lineJoinStyle = .round
            cap.lineWidth = 1.4

            // Stem under the cap.
            let stem = NSBezierPath(roundedRect: NSRect(x: 6.3, y: 2, width: 2.4, height: 3.5), xRadius: 0.5, yRadius: 0.5)

            if active {
                cap.fill()
                cap.stroke()  // the stroke rounds off the corners
                stem.fill()
                // Carve the top face so the cap reads as 3D at 18 pt.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(roundedRect: NSRect(x: 4.6, y: 9.4, width: 5.8, height: 3), xRadius: 1, yRadius: 1).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver

                for radius in [3.0, 5.4] {
                    let wave = NSBezierPath()
                    wave.appendArc(withCenter: NSPoint(x: 13.2, y: 11.5), radius: radius, startAngle: -35, endAngle: 55)
                    wave.lineWidth = 1.3
                    wave.lineCapStyle = .round
                    wave.stroke()
                }
            } else {
                cap.stroke()
                stem.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "Mechanify, sounds on" : "Mechanify, sounds off"
        return image
    }
}
