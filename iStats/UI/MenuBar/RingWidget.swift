import AppKit
import iStatsCore

extension MenuBarIconRenderer {
    /// One arc of a ring gauge: a share of the full circle.
    struct RingArc {
        let fraction: Int
        let color: NSColor
        let roundCap: Bool
    }

    /// Draws a donut gauge (18 pt bare, 32 x 22 with a rotated label); arcs stack clockwise from 12 o'clock.
    static func drawRing(arcs: [RingArc], label: String?, isTemplate: Bool = false) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let size = NSSize(width: hasLabel ? 32.0 : 18.0, height: hasLabel ? 22.0 : 18.0)

        let image = NSImage(size: size, flipped: false) { bounds in
            let gaugeBounds: NSRect
            if hasLabel {
                drawVerticalCategoryText(label!, in: NSRect(x: 2.0, y: 2.0, width: 9.5, height: 18.0), color: .labelColor)
                gaugeBounds = NSRect(x: 13.5, y: 2.0, width: 18.0, height: 18.0)
            } else {
                gaugeBounds = bounds
            }

            let center = NSPoint(x: gaugeBounds.midX, y: gaugeBounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.6

            let track = NSBezierPath(ovalIn: gaugeBounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            (isTemplate ? NSColor.labelColor.withAlphaComponent(0.20) : NSColor.secondaryLabelColor.withAlphaComponent(0.20)).setStroke()
            track.stroke()

            var startAngle: CGFloat = 90.0
            for arc in arcs where arc.fraction > 0 {
                let sweep = CGFloat(360.0 * Double(arc.fraction) / 100.0)
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
                path.lineWidth = lineWidth
                path.lineCapStyle = arc.roundCap ? .round : .butt
                arc.color.setStroke()
                path.stroke()
                startAngle -= sweep
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
}

/// Renders donut gauges for CPU (user + system arcs) and single-arc rings for everything else.
@MainActor
struct RingWidget: WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage {
        let f = model.fractions
        let isTemplate = model.prefersTemplate
        if model.layout == .cpuRing {
            let userColor: NSColor
            let sysColor: NSColor
            switch model.colorRole {
            case .label:
                userColor = .labelColor
                sysColor = NSColor.labelColor.withAlphaComponent(0.50)
            case .status(let level):
                let s = CategoryPalette.statusNSColor(for: level)
                userColor = s
                sysColor = s.withAlphaComponent(0.60)
            case .category:
                userColor = CategoryPalette.nsColor(for: .cpu)
                sysColor = NSColor(CategoryPalette.Series.cpuSystem).withAlphaComponent(0.70)
            }
            return MenuBarIconRenderer.drawRing(
                arcs: [
                    .init(fraction: f[0], color: userColor, roundCap: true),
                    .init(fraction: f[1], color: sysColor, roundCap: false)
                ],
                label: model.label,
                isTemplate: isTemplate
            )
        }
        return MenuBarIconRenderer.drawRing(
            arcs: [.init(fraction: f.first ?? 0, color: WidgetColor.resolve(model.colorRole, category: model.category), roundCap: true)],
            label: model.label,
            isTemplate: isTemplate
        )
    }
}
