import AppKit
import CoreText
import SwiftUI
import iStatsCore

extension MenuBarIconRenderer {
    /// Helper that formats numeric values with a clean suffix symbol (%, °, k, etc.)
    /// matching the modern elegant typography preferred by the user.
    static func formatCompactValueAttributedString(
        value: String,
        color: NSColor
    ) -> NSAttributedString {
        let attrString = NSMutableAttributedString()
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        let digits = String(trimmed.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" }))
        let suffix = String(trimmed.dropFirst(digits.count))

        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        let suffixFont = NSFont.systemFont(ofSize: 9.0, weight: .medium)

        let digitAttrs: [NSAttributedString.Key: Any] = [
            .font: digitFont,
            .foregroundColor: color
        ]
        attrString.append(NSAttributedString(string: digits.isEmpty ? trimmed : digits, attributes: digitAttrs))

        if !digits.isEmpty && !suffix.isEmpty {
            let offset: CGFloat = suffix.contains("°") ? 1.5 : 0.5
            let suffixAttrs: [NSAttributedString.Key: Any] = [
                .font: suffixFont,
                .foregroundColor: color,
                .baselineOffset: offset
            ]
            attrString.append(NSAttributedString(string: suffix, attributes: suffixAttrs))
        }

        return attrString
    }

    /// Smallest text size used by any menu bar widget (points).
    public static let minimumWidgetFontSize: CGFloat = 9.0

    /// Draws a category acronym (e.g. "SSD", "CPU", "RAM") as one rotated line that reads bottom to top.
    /// Always uses `minimumWidgetFontSize`; kerning tightens (instead of shrinking the font) to fit `rect`.
    public static func drawVerticalCategoryText(
        _ text: String,
        in rect: NSRect,
        color: NSColor = .labelColor
    ) {
        guard !text.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }

        let font = NSFont.monospacedSystemFont(ofSize: minimumWidgetFontSize, weight: .heavy)
        func attributed(kern: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text.uppercased(), attributes: [.font: font, .foregroundColor: color, .kern: kern])
        }
        var str = attributed(kern: 0.0)
        var kern: CGFloat = 0.0
        while str.size().width > rect.height && kern > -2.0 {
            kern -= 0.25
            str = attributed(kern: kern)
        }
        let size = str.size()

        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: .pi / 2)
        str.draw(at: NSPoint(x: -size.width / 2.0, y: -size.height / 2.0))
        context.restoreGState()
    }

    /// Draws an authentic iStat Menus high-DPI rounded capsule pill load bar.
    public static func drawCapsulePill(
        in rect: NSRect,
        percentage: Double,
        fillColor: NSColor? = nil,
        borderColor: NSColor? = nil,
        trackColor: NSColor? = nil
    ) {
        let radius = rect.width / 2.0
        let outerPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let bg = trackColor ?? NSColor.labelColor.withAlphaComponent(0.12)
        bg.setFill()
        outerPath.fill()

        let border = borderColor ?? NSColor.labelColor.withAlphaComponent(0.50)
        outerPath.lineWidth = 1.2
        border.setStroke()
        outerPath.stroke()

        let clamped = min(max(percentage, 0.0), 100.0)
        if clamped > 0 {
            let innerInset: CGFloat = 1.4
            let innerRect = rect.insetBy(dx: innerInset, dy: innerInset)
            let innerRadius = max(innerRect.width / 2.0, 1.0)
            let innerClipPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

            NSGraphicsContext.saveGraphicsState()
            innerClipPath.addClip()

            let fillHeight = max(innerRect.height * CGFloat(clamped / 100.0), 2.0)
            let fillRect = NSRect(
                x: innerRect.minX,
                y: innerRect.minY,
                width: innerRect.width,
                height: fillHeight
            )
            let fill = fillColor ?? NSColor.labelColor
            fill.setFill()
            fillRect.fill()

            NSGraphicsContext.restoreGraphicsState()
        }
    }

}
