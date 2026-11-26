import AppKit
import CoreText
import SwiftUI
import iStatsCore

extension MenuBarIconRenderer {
    /// Draws clean, elegant 2-line stacked high-density typography with generous vertical spacing
    /// and strict invariant fixed-width preventing menu bar horizontal jitter.
    public static func drawCategoryStackedText(
        title: String,
        value: String,
        fixedWidth: CGFloat = 32.0,
        titleColor: NSColor? = nil,
        valueColor: NSColor? = nil,
        statusDotColor: NSColor? = nil,
        useInternalCache: Bool = true
    ) -> NSImage {
        let isTemplate = (titleColor == nil && valueColor == nil && statusDotColor == nil)
        let dotHash = statusDotColor?.hashValue ?? 0
        let cacheKey = "stacked:\(title):\(value):\(fixedWidth):\(isTemplate ? 0 : (titleColor?.hashValue ?? 0)):\(isTemplate ? 0 : (valueColor?.hashValue ?? 0)):\(dotHash)" as NSString
        if useInternalCache, let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let tColor = titleColor ?? NSColor.labelColor.withAlphaComponent(0.90)
        let vColor = valueColor ?? NSColor.labelColor

        let titleFont = NSFont.systemFont(ofSize: 9.0, weight: .medium)
        let tAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: tColor,
            .kern: 0.10
        ]
        let titleAttrString = NSAttributedString(string: title.uppercased(), attributes: tAttrs)
        let valueAttrString = formatCompactValueAttributedString(value: value, color: vColor)

        let tSize = titleAttrString.size()
        let vSize = valueAttrString.size()

        let canvasWidth = max(fixedWidth, max(tSize.width, vSize.width) + 2.0)
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let tX = floor(max(0.0, (bounds.width - tSize.width) / 2.0))
            let vX = floor(max(0.0, (bounds.width - vSize.width) / 2.0))

            let vY: CGFloat = -1.8
            let tY: CGFloat = 10.5

            titleAttrString.draw(at: NSPoint(x: tX, y: tY))
            valueAttrString.draw(at: NSPoint(x: vX, y: vY))

            if let dotColor = statusDotColor {
                let dotRect = NSRect(x: bounds.maxX - 4.5, y: bounds.maxY - 4.5, width: 3.0, height: 3.0)
                let dot = NSBezierPath(ovalIn: dotRect)
                dotColor.setFill()
                dot.fill()
            }

            return true
        }
        image.isTemplate = isTemplate
        if useInternalCache {
            imageCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

}

/// Renders `labelValue` widgets: a category label over a value.
@MainActor
struct ValueWidget: WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage {
        let valueColor = WidgetColor.optional(model.colorRole, category: model.category)
        let dotColor: NSColor? = (model.flags.first == true && !model.prefersTemplate)
            ? CategoryPalette.statusNSColor(for: model.status)
            : nil
        return MenuBarIconRenderer.drawCategoryStackedText(
            title: model.label ?? "",
            value: model.texts.first ?? "--",
            fixedWidth: WidgetMetrics.width(model.widthClass),
            valueColor: valueColor,
            statusDotColor: dotColor,
            useInternalCache: false
        )
    }
}
