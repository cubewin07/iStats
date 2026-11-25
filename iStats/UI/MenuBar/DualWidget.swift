import AppKit
import CoreText
import SwiftUI
import iStatsCore

extension MenuBarIconRenderer {
    /// Draws authentic iStat Menus 2-line stacked typography with left-aligned prefix icons/labels
    /// within a fixed invariant width canvas that prevents menu bar horizontal jitter.
    public static func drawStackedTwoLineText(
        prefix1: String,
        value1: String,
        prefix2: String,
        value2: String,
        minWidth: CGFloat = 60.0,
        color1: NSColor? = nil,
        color2: NSColor? = nil,
        prefixColor1: NSColor? = nil,
        prefixColor2: NSColor? = nil
    ) -> NSImage {
        let pFont = NSFont.systemFont(ofSize: 9.0, weight: .bold)
        let vFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)

        let pAttrs1: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor1 ?? color1 ?? NSColor.labelColor
        ]
        let pAttrs2: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor2 ?? color2 ?? NSColor.labelColor
        ]
        let vAttrs1: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color1 ?? NSColor.labelColor
        ]
        let vAttrs2: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color2 ?? NSColor.labelColor
        ]

        let sp1 = (prefix1 as NSString).size(withAttributes: pAttrs1)
        let sp2 = (prefix2 as NSString).size(withAttributes: pAttrs2)
        let sv1 = (value1 as NSString).size(withAttributes: vAttrs1)
        let sv2 = (value2 as NSString).size(withAttributes: vAttrs2)

        let hasPrefix = !prefix1.isEmpty || !prefix2.isEmpty
        let maxPrefixWidth = hasPrefix ? max(sp1.width, sp2.width) : 0.0
        let maxValWidth = max(sv1.width, sv2.width)

        let leftPadding: CGFloat = 2.0
        let rightPadding: CGFloat = 2.0
        let prefixGap: CGFloat = hasPrefix ? 2.0 : 0.0

        let neededWidth = leftPadding + maxPrefixWidth + prefixGap + maxValWidth + rightPadding
        let canvasWidth = max(minWidth, ceil(neededWidth))
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let y1: CGFloat = 11.5
            let y2: CGFloat = 2.0

            if hasPrefix {
                if !prefix1.isEmpty {
                    (prefix1 as NSString).draw(at: NSPoint(x: leftPadding, y: y1), withAttributes: pAttrs1)
                }
                if !prefix2.isEmpty {
                    (prefix2 as NSString).draw(at: NSPoint(x: leftPadding, y: y2), withAttributes: pAttrs2)
                }

                let vX1 = bounds.maxX - rightPadding - sv1.width
                let vX2 = bounds.maxX - rightPadding - sv2.width
                (value1 as NSString).draw(at: NSPoint(x: max(leftPadding + maxPrefixWidth + 1.0, vX1), y: y1), withAttributes: vAttrs1)
                (value2 as NSString).draw(at: NSPoint(x: max(leftPadding + maxPrefixWidth + 1.0, vX2), y: y2), withAttributes: vAttrs2)
            } else {
                let vX1 = floor((bounds.width - sv1.width) / 2.0)
                let vX2 = floor((bounds.width - sv2.width) / 2.0)
                (value1 as NSString).draw(at: NSPoint(x: max(leftPadding, vX1), y: y1), withAttributes: vAttrs1)
                (value2 as NSString).draw(at: NSPoint(x: max(leftPadding, vX2), y: y2), withAttributes: vAttrs2)
            }

            return true
        }
        image.isTemplate = (color1 == nil && color2 == nil && prefixColor1 == nil && prefixColor2 == nil)
        return image
    }

    /// Draws single-line throughput with fixed-width tabular slots preventing menu bar jitter.
    public static func drawSingleLineThroughput(
        prefix1: String,
        value1: String,
        prefix2: String,
        value2: String,
        fixedWidth: CGFloat = 82.0,
        color1: NSColor? = nil,
        color2: NSColor? = nil,
        prefixColor1: NSColor? = nil,
        prefixColor2: NSColor? = nil,
        useInternalCache: Bool = true
    ) -> NSImage {
        let c1Hash = color1?.hashValue ?? 0
        let c2Hash = color2?.hashValue ?? 0
        let p1Hash = prefixColor1?.hashValue ?? 0
        let p2Hash = prefixColor2?.hashValue ?? 0
        let cacheKey = "singleLineTp:\(prefix1):\(value1):\(prefix2):\(value2):\(fixedWidth):\(c1Hash):\(c2Hash):\(p1Hash):\(p2Hash)" as NSString
        if useInternalCache, let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let pFont = NSFont.systemFont(ofSize: 9.0, weight: .bold)
        let vFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)

        let pAttrs1: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor1 ?? color1 ?? NSColor.labelColor
        ]
        let pAttrs2: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor2 ?? color2 ?? NSColor.labelColor
        ]
        let vAttrs1: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color1 ?? NSColor.labelColor
        ]
        let vAttrs2: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color2 ?? NSColor.labelColor
        ]

        let sp1 = (prefix1 as NSString).size(withAttributes: pAttrs1)
        let sp2 = (prefix2 as NSString).size(withAttributes: pAttrs2)
        let sv1 = (value1 as NSString).size(withAttributes: vAttrs1)
        let sv2 = (value2 as NSString).size(withAttributes: vAttrs2)

        let size = NSSize(width: fixedWidth, height: 22)
        let halfWidth = (fixedWidth - 6.0) / 2.0

        let image = NSImage(size: size, flipped: false) { bounds in
            let y = floor((bounds.height - max(sp1.height, sv1.height)) / 2.0)

            // Slot 1: [2.0 ... 2.0 + halfWidth]
            let slot1X: CGFloat = 2.0
            (prefix1 as NSString).draw(at: NSPoint(x: slot1X, y: y), withAttributes: pAttrs1)
            let v1X = slot1X + halfWidth - sv1.width
            (value1 as NSString).draw(at: NSPoint(x: max(slot1X + sp1.width + 1.0, v1X), y: y), withAttributes: vAttrs1)

            // Slot 2: [slot2X ... bounds.maxX - 2.0]
            let slot2X: CGFloat = slot1X + halfWidth + 2.0
            (prefix2 as NSString).draw(at: NSPoint(x: slot2X, y: y), withAttributes: pAttrs2)
            let v2X = bounds.maxX - 2.0 - sv2.width
            (value2 as NSString).draw(at: NSPoint(x: max(slot2X + sp2.width + 1.0, v2X), y: y), withAttributes: vAttrs2)

            return true
        }
        image.isTemplate = (color1 == nil && color2 == nil && prefixColor1 == nil && prefixColor2 == nil)
        if useInternalCache {
            imageCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    /// Draws a dual capsule load bar widget with vertical category label on the left.
    public static func drawDualCapsuleBar(
        label: String,
        leftPercentage: Double,
        rightPercentage: Double,
        leftColor: NSColor? = nil,
        rightColor: NSColor? = nil,
        labelColor: NSColor? = nil
    ) -> NSImage {
        let size = NSSize(width: 36, height: 22)
        let image = NSImage(size: size, flipped: false) { bounds in
            let barWidth: CGFloat = 8.5
            let barHeight: CGFloat = 20.0
            let barY: CGFloat = (bounds.height - barHeight) / 2.0

            let textRect = NSRect(x: 2.0, y: barY, width: 9.5, height: barHeight)
            let leftBarRect = NSRect(x: 14.5, y: barY, width: barWidth, height: barHeight)
            let rightBarRect = NSRect(x: 25.5, y: barY, width: barWidth, height: barHeight)

            drawVerticalCategoryText(label, in: textRect, color: labelColor ?? .labelColor)
            drawCapsulePill(in: leftBarRect, percentage: leftPercentage, fillColor: leftColor)
            drawCapsulePill(in: rightBarRect, percentage: rightPercentage, fillColor: rightColor)

            return true
        }
        image.isTemplate = (leftColor == nil && rightColor == nil && labelColor == nil)
        return image
    }

}

/// Renders two-value widgets: two-line text, single-line throughput and dual capsule bars.
@MainActor
struct DualWidget: WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage {
        switch model.layout {
        case .singleLine:
            let second: NSColor = model.category == .network
                ? NSColor(CategoryPalette.Series.networkUpload)
                : NSColor(CategoryPalette.Series.diskWrite)
            return MenuBarIconRenderer.drawSingleLineThroughput(
                prefix1: model.prefixes[0],
                value1: model.texts[0],
                prefix2: model.prefixes[1],
                value2: model.texts[1],
                fixedWidth: WidgetMetrics.width(model.widthClass),
                color1: CategoryPalette.nsColor(for: model.category),
                color2: second,
                useInternalCache: false
            )

        case .dualCapsule:
            let left: NSColor
            let right: NSColor
            switch model.category {
            case .fan:
                left = CategoryPalette.nsColor(for: .fan)
                right = CategoryPalette.nsDeep(for: .fan)
            default:
                if model.flags.first == true {
                    left = NSColor(CategoryPalette.Series.cpuEfficiency)
                    right = CategoryPalette.nsColor(for: .cpu)
                } else {
                    left = CategoryPalette.nsColor(for: .cpu)
                    right = NSColor(CategoryPalette.Series.cpuSystem)
                }
            }
            return MenuBarIconRenderer.drawDualCapsuleBar(
                label: model.label ?? "",
                leftPercentage: Double(model.fractions[0]),
                rightPercentage: Double(model.fractions[1]),
                leftColor: left,
                rightColor: right
            )

        default:
            var c1: NSColor?
            var c2: NSColor?
            if model.colorRole == .category {
                if model.category == .fan {
                    c1 = CategoryPalette.nsColor(for: .fan)
                    c2 = CategoryPalette.nsDeep(for: .fan)
                } else {
                    c1 = CategoryPalette.nsColor(for: model.category)
                    c2 = .secondaryLabelColor
                }
            }
            let fanColors = model.category == .fan
            return MenuBarIconRenderer.drawStackedTwoLineText(
                prefix1: model.prefixes[0],
                value1: model.texts[0],
                prefix2: model.prefixes[1],
                value2: model.texts[1],
                minWidth: WidgetMetrics.width(model.widthClass),
                color1: c1,
                color2: c2,
                prefixColor1: fanColors ? c1 : nil,
                prefixColor2: fanColors ? c2 : nil
            )
        }
    }
}
