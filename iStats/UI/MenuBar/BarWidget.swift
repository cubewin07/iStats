import AppKit
import CoreText
import SwiftUI
import iStatsCore

extension MenuBarIconRenderer {
    /// Draws a single capsule load bar widget with a vertical category label on the left.
    public static func drawSingleCapsuleBar(
        label: String,
        percentage: Double,
        barColor: NSColor? = nil,
        labelColor: NSColor? = nil
    ) -> NSImage {
        let canvasWidth: CGFloat = label.isEmpty ? 13.0 : 25.0
        let size = NSSize(width: canvasWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { bounds in
            let barWidth: CGFloat = 8.5
            let barHeight: CGFloat = 20.0
            let barY: CGFloat = (bounds.height - barHeight) / 2.0

            if label.isEmpty {
                let barRect = NSRect(x: (bounds.width - barWidth) / 2.0, y: barY, width: barWidth, height: barHeight)
                drawCapsulePill(in: barRect, percentage: percentage, fillColor: barColor)
            } else {
                let textRect = NSRect(x: 2.0, y: barY, width: 9.5, height: barHeight)
                let barRect = NSRect(x: 14.5, y: barY, width: barWidth, height: barHeight)

                drawVerticalCategoryText(label, in: textRect, color: labelColor ?? .labelColor)
                drawCapsulePill(in: barRect, percentage: percentage, fillColor: barColor)
            }
            return true
        }
        image.isTemplate = (barColor == nil && labelColor == nil)
        return image
    }

    /// Draws authentic 3-segment Memory allocation bar (App: Blue, Wired: Red, Compressed: Gold)
    /// with vertical "RAM" category label on the left.
    public static func drawMemoryStackedBar(ratio: Int, app: Int, wired: Int, compressed: Int, hasSegments: Bool) -> NSImage {
        let textWidth: CGFloat = 9.5
        let barWidth: CGFloat = 8.5
        let barHeight: CGFloat = 20.0
        let canvasWidth: CGFloat = 25.0
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let barY: CGFloat = (bounds.height - barHeight) / 2.0
            let textRect = NSRect(x: 2.0, y: barY, width: textWidth, height: barHeight)
            let barRect = NSRect(x: 14.5, y: barY, width: barWidth, height: barHeight)

            drawVerticalCategoryText("RAM", in: textRect, color: .labelColor)

            let radius = barRect.width / 2.0
            let outerPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
            let bg = NSColor.labelColor.withAlphaComponent(0.12)
            bg.setFill()
            outerPath.fill()

            outerPath.lineWidth = 1.2
            NSColor.labelColor.withAlphaComponent(0.50).setStroke()
            outerPath.stroke()

            let innerInset: CGFloat = 1.4
            let innerRect = barRect.insetBy(dx: innerInset, dy: innerInset)
            let innerRadius = max(innerRect.width / 2.0, 1.0)
            let innerClipPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

            NSGraphicsContext.saveGraphicsState()
            innerClipPath.addClip()

            if hasSegments {
                // 3 segments only: App (Blue), Wired, Compressed
                let segments: [(fraction: Double, color: NSColor)] = [
                    (Double(app) / 100.0, NSColor(CategoryPalette.Series.memoryApp)),
                    (Double(wired) / 100.0, NSColor(CategoryPalette.Series.memoryWired)),
                    (Double(compressed) / 100.0, NSColor(CategoryPalette.Series.memoryCompressed))
                ]

                var currentY = innerRect.minY
                let gap: CGFloat = 0.5

                for seg in segments where seg.fraction > 0 {
                    let segH = max(innerRect.height * CGFloat(seg.fraction), 1.0)
                    let segRect = NSRect(
                        x: innerRect.minX,
                        y: currentY,
                        width: innerRect.width,
                        height: max(segH - gap, 0.5)
                    )
                    seg.color.setFill()
                    segRect.fill()
                    currentY += segH
                }
            } else {
                let clamped = min(max(Double(ratio), 0.0), 100.0)
                if clamped > 0 {
                    let fillHeight = max(innerRect.height * CGFloat(clamped / 100.0), 2.0)
                    let fillRect = NSRect(x: innerRect.minX, y: innerRect.minY, width: innerRect.width, height: fillHeight)
                    CategoryPalette.statusNSColor(for: .fine).setFill()
                    fillRect.fill()
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

}

/// Renders capsule bars: single capsule and the memory allocation capsule.
@MainActor
struct BarWidget: WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage {
        let f = model.fractions
        if model.layout == .memoryAllocation {
            return MenuBarIconRenderer.drawMemoryStackedBar(
                ratio: f[0], app: f[1], wired: f[2], compressed: f[3], hasSegments: model.flags.first == true
            )
        }
        return MenuBarIconRenderer.drawSingleCapsuleBar(
            label: model.label ?? "",
            percentage: Double(f.first ?? 0),
            barColor: WidgetColor.resolve(model.colorRole, category: model.category)
        )
    }
}
