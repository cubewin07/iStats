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

    /// Draws authentic 3-segment Memory allocation bar (App, Wired, Compressed)
    /// with vertical "RAM" category label on the left. Honors `colorRole` for template/status/category modes.
    public static func drawMemoryStackedBar(
        ratio: Int,
        app: Int,
        wired: Int,
        compressed: Int,
        hasSegments: Bool,
        colorRole: WidgetColorRole = .category
    ) -> NSImage {
        let textWidth: CGFloat = 9.5
        let barWidth: CGFloat = 8.5
        let barHeight: CGFloat = 20.0
        let canvasWidth: CGFloat = 25.0
        let size = NSSize(width: canvasWidth, height: 22)
        let isTemplate = (colorRole == .label)

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

            let appColor: NSColor
            let wiredColor: NSColor
            let compressedColor: NSColor
            let fallbackColor: NSColor

            switch colorRole {
            case .label:
                appColor = .labelColor
                wiredColor = NSColor.labelColor.withAlphaComponent(0.65)
                compressedColor = NSColor.labelColor.withAlphaComponent(0.38)
                fallbackColor = .labelColor
            case .status(let level):
                let s = CategoryPalette.statusNSColor(for: level)
                appColor = s
                wiredColor = s.withAlphaComponent(0.75)
                compressedColor = s.withAlphaComponent(0.45)
                fallbackColor = s
            case .category:
                appColor = NSColor(CategoryPalette.Series.memoryApp)
                wiredColor = NSColor(CategoryPalette.Series.memoryWired)
                compressedColor = NSColor(CategoryPalette.Series.memoryCompressed)
                fallbackColor = CategoryPalette.nsColor(for: .memory)
            }

            if hasSegments {
                let segments: [(fraction: Double, color: NSColor)] = [
                    (Double(app) / 100.0, appColor),
                    (Double(wired) / 100.0, wiredColor),
                    (Double(compressed) / 100.0, compressedColor)
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
                    fallbackColor.setFill()
                    fillRect.fill()
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = isTemplate
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
                ratio: f[0],
                app: f[1],
                wired: f[2],
                compressed: f[3],
                hasSegments: model.flags.first == true,
                colorRole: model.colorRole
            )
        }
        return MenuBarIconRenderer.drawSingleCapsuleBar(
            label: model.label ?? "",
            percentage: Double(f.first ?? 0),
            barColor: WidgetColor.optional(model.colorRole, category: model.category)
        )
    }
}
