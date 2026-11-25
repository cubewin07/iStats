import AppKit
import CoreText
import SwiftUI
import iStatsCore

extension MenuBarIconRenderer {
    public static func computeDecayMax(values: [Double], floor: Double) -> Double {
        let peak = values.max() ?? floor
        return max(peak, floor)
    }

    /// Draws mirrored duplex network history graph (Inbound above midline, Outbound below midline).
    public static func drawNetworkSplitDuplexGraph(
        inHistory: [Double],
        outHistory: [Double],
        label: String? = nil,
        colorRole: WidgetColorRole = .category
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)
        let isTemplate = (colorRole == .label)

        let inStroke: NSColor
        let outStroke: NSColor
        switch colorRole {
        case .label:
            inStroke = .labelColor
            outStroke = NSColor.labelColor.withAlphaComponent(0.58)
        case .status(let level):
            let s = CategoryPalette.statusNSColor(for: level)
            inStroke = s
            outStroke = s.withAlphaComponent(0.68)
        case .category:
            inStroke = CategoryPalette.nsColor(for: .network)
            outStroke = NSColor(CategoryPalette.Series.networkUpload)
        }

        let image = NSImage(size: size, flipped: false) { bounds in
            let graphBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                graphBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                graphBounds = bounds
            }

            let midY = graphBounds.midY

            // Baseline center divider line
            let centerLine = NSBezierPath()
            centerLine.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))
            centerLine.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
            centerLine.lineWidth = 0.6
            (isTemplate ? NSColor.labelColor.withAlphaComponent(0.35) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            centerLine.stroke()

            let inMax = max(inHistory.max() ?? 1024.0, 1024.0)
            let outMax = max(outHistory.max() ?? 1024.0, 1024.0)

            let count = max(max(inHistory.count, outHistory.count), 2)
            let stepX = (graphBounds.width - 2.0) / CGFloat(count - 1)

            // 1. Inbound (Download) - Waves scrolling above midline
            if inHistory.count >= 2 {
                let inFill = NSBezierPath()
                let inLine = NSBezierPath()
                inFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in inHistory.enumerated() {
                    let clamped = min(max(val, 0.0), inMax)
                    let h = CGFloat(clamped / inMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY + h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        inLine.move(to: pt)
                        inFill.line(to: pt)
                    } else {
                        inLine.line(to: pt)
                        inFill.line(to: pt)
                    }
                }
                inFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                inFill.close()
                inStroke.withAlphaComponent(0.28).setFill()
                inFill.fill()

                inLine.lineWidth = 1.2
                inLine.lineJoinStyle = .round
                inStroke.setStroke()
                inLine.stroke()
            }

            // 2. Outbound (Upload) - Waves scrolling below midline
            if outHistory.count >= 2 {
                let outFill = NSBezierPath()
                let outLine = NSBezierPath()
                outFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in outHistory.enumerated() {
                    let clamped = min(max(val, 0.0), outMax)
                    let h = CGFloat(clamped / outMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY - h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        outLine.move(to: pt)
                        outFill.line(to: pt)
                    } else {
                        outLine.line(to: pt)
                        outFill.line(to: pt)
                    }
                }
                outFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                outFill.close()
                outStroke.withAlphaComponent(0.25).setFill()
                outFill.fill()

                outLine.lineWidth = 1.2
                outLine.lineJoinStyle = .round
                outStroke.setStroke()
                outLine.stroke()
            }

            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    /// Draws mirrored duplex disk I/O history graph (Read above midline, Write below midline).
    public static func drawDiskSplitDuplexGraph(
        readHistory: [Double],
        writeHistory: [Double],
        label: String? = nil,
        colorRole: WidgetColorRole = .category
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)
        let isTemplate = (colorRole == .label)

        let readStroke: NSColor
        let writeStroke: NSColor
        switch colorRole {
        case .label:
            readStroke = .labelColor
            writeStroke = NSColor.labelColor.withAlphaComponent(0.58)
        case .status(let level):
            let s = CategoryPalette.statusNSColor(for: level)
            readStroke = s
            writeStroke = s.withAlphaComponent(0.68)
        case .category:
            readStroke = CategoryPalette.nsColor(for: .disk)
            writeStroke = NSColor(CategoryPalette.Series.diskWrite)
        }

        let image = NSImage(size: size, flipped: false) { bounds in
            let graphBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                graphBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                graphBounds = bounds
            }

            let midY = graphBounds.midY

            let centerLine = NSBezierPath()
            centerLine.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))
            centerLine.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
            centerLine.lineWidth = 0.6
            (isTemplate ? NSColor.labelColor.withAlphaComponent(0.35) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            centerLine.stroke()

            let rMax = computeDecayMax(values: readHistory, floor: 1024.0 * 1024.0)
            let wMax = computeDecayMax(values: writeHistory, floor: 1024.0 * 1024.0)

            let count = max(max(readHistory.count, writeHistory.count), 2)
            let stepX = (graphBounds.width - 2.0) / CGFloat(count - 1)

            // Read above midline
            if readHistory.count >= 2 {
                let rFill = NSBezierPath()
                let rLine = NSBezierPath()
                rFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in readHistory.enumerated() {
                    let clamped = min(max(val, 0.0), rMax)
                    let h = CGFloat(clamped / rMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY + h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        rLine.move(to: pt)
                        rFill.line(to: pt)
                    } else {
                        rLine.line(to: pt)
                        rFill.line(to: pt)
                    }
                }
                rFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                rFill.close()
                readStroke.withAlphaComponent(0.28).setFill()
                rFill.fill()

                rLine.lineWidth = 1.2
                rLine.lineJoinStyle = .round
                readStroke.setStroke()
                rLine.stroke()
            }

            // Write below midline
            if writeHistory.count >= 2 {
                let wFill = NSBezierPath()
                let wLine = NSBezierPath()
                wFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in writeHistory.enumerated() {
                    let clamped = min(max(val, 0.0), wMax)
                    let h = CGFloat(clamped / wMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY - h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        wLine.move(to: pt)
                        wFill.line(to: pt)
                    } else {
                        wLine.line(to: pt)
                        wFill.line(to: pt)
                    }
                }
                wFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                wFill.close()
                writeStroke.withAlphaComponent(0.25).setFill()
                wFill.fill()

                wLine.lineWidth = 1.2
                wLine.lineJoinStyle = .round
                writeStroke.setStroke()
                wLine.stroke()
            }

            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    public static func drawCPUSparkline(
        history: [Double],
        userHistory: [Double] = [],
        systemHistory: [Double] = [],
        label: String? = nil,
        colorRole: WidgetColorRole = .category
    ) -> NSImage {
        let isTemplate = (colorRole == .label)
        let userColor: NSColor
        let sysColor: NSColor
        switch colorRole {
        case .label:
            userColor = .labelColor
            sysColor = NSColor.labelColor.withAlphaComponent(0.55)
        case .status(let level):
            let s = CategoryPalette.statusNSColor(for: level)
            userColor = s
            sysColor = s.withAlphaComponent(0.65)
        case .category:
            userColor = CategoryPalette.nsColor(for: .cpu)
            sysColor = NSColor(CategoryPalette.Series.cpuSystem)
        }

        guard userHistory.count == history.count && systemHistory.count == history.count && history.count >= 2 else {
            return drawColoredSparkline(
                values: history,
                maxValue: 100.0,
                strokeColor: userColor,
                fillColor: userColor.withAlphaComponent(0.25),
                label: label,
                isTemplate: isTemplate
            )
        }

        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let sparkBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                sparkBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                sparkBounds = bounds
            }

            let innerBounds = sparkBounds.insetBy(dx: 1.5, dy: 1.5)
            let stepX = innerBounds.width / CGFloat(max(history.count - 1, 1))

            let userLine = NSBezierPath()
            let userFill = NSBezierPath()
            userFill.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            let totalLine = NSBezierPath()
            let totalFill = NSBezierPath()
            totalFill.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            var lastUserPt = NSPoint(x: innerBounds.minX, y: innerBounds.minY)
            var lastTotalPt = NSPoint(x: innerBounds.minX, y: innerBounds.minY)

            for (idx, uVal) in userHistory.enumerated() {
                let sVal = systemHistory[idx]
                let totalVal = min(max(uVal + sVal, 0.0), 100.0)
                let clampedU = min(max(uVal, 0.0), 100.0)

                let x = innerBounds.minX + (CGFloat(idx) * stepX)
                let uY = innerBounds.minY + (innerBounds.height * CGFloat(clampedU / 100.0))
                let tY = innerBounds.minY + (innerBounds.height * CGFloat(totalVal / 100.0))

                let uPt = NSPoint(x: x, y: uY)
                let tPt = NSPoint(x: x, y: tY)
                lastUserPt = uPt
                lastTotalPt = tPt

                if idx == 0 {
                    userLine.move(to: uPt)
                    userFill.line(to: uPt)
                    totalLine.move(to: tPt)
                    totalFill.line(to: tPt)
                } else {
                    userLine.line(to: uPt)
                    userFill.line(to: uPt)
                    totalLine.line(to: tPt)
                    totalFill.line(to: tPt)
                }
            }

            totalFill.line(to: NSPoint(x: lastTotalPt.x, y: innerBounds.minY))
            totalFill.close()
            sysColor.withAlphaComponent(0.25).setFill()
            totalFill.fill()

            userFill.line(to: NSPoint(x: lastUserPt.x, y: innerBounds.minY))
            userFill.close()
            userColor.withAlphaComponent(0.35).setFill()
            userFill.fill()

            userLine.lineWidth = 1.2
            userLine.lineJoinStyle = .round
            userColor.setStroke()
            userLine.stroke()

            totalLine.lineWidth = 1.2
            totalLine.lineJoinStyle = .round
            sysColor.withAlphaComponent(0.70).setStroke()
            totalLine.stroke()

            let dotRect = NSRect(x: lastTotalPt.x - 1.4, y: lastTotalPt.y - 1.4, width: 2.8, height: 2.8)
            let dot = NSBezierPath(ovalIn: dotRect)
            userColor.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    /// Draws a colored or template history sparkline chart with area fill and peak dot.
    public static func drawColoredSparkline(
        values: [Double],
        maxValue: Double,
        strokeColor: NSColor,
        fillColor: NSColor,
        label: String? = nil,
        isTemplate: Bool = false
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let sparkBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                sparkBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                sparkBounds = bounds
            }

            guard values.count >= 2 else {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: sparkBounds.minX + 1.0, y: sparkBounds.minY + 2.0))
                path.line(to: NSPoint(x: sparkBounds.maxX - 1.0, y: sparkBounds.minY + 2.0))
                path.lineWidth = 1.0
                (isTemplate ? NSColor.labelColor.withAlphaComponent(0.35) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
                path.stroke()
                return true
            }

            let maxVal = max(maxValue, 1.0)
            let innerBounds = sparkBounds.insetBy(dx: 1.5, dy: 1.5)
            let stepX = innerBounds.width / CGFloat(max(values.count - 1, 1))

            let linePath = NSBezierPath()
            let fillPath = NSBezierPath()
            fillPath.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            var lastPoint = NSPoint(x: innerBounds.minX, y: innerBounds.minY)

            for (index, val) in values.enumerated() {
                let clamped = min(max(val, 0.0), maxVal)
                let y = innerBounds.minY + (innerBounds.height * CGFloat(clamped / maxVal))
                let x = innerBounds.minX + (CGFloat(index) * stepX)
                let pt = NSPoint(x: x, y: y)
                lastPoint = pt

                if index == 0 {
                    linePath.move(to: pt)
                    fillPath.line(to: pt)
                } else {
                    linePath.line(to: pt)
                    fillPath.line(to: pt)
                }
            }

            fillPath.line(to: NSPoint(x: lastPoint.x, y: innerBounds.minY))
            fillPath.close()
            fillColor.setFill()
            fillPath.fill()

            linePath.lineWidth = 1.4
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            strokeColor.setStroke()
            linePath.stroke()

            let dotRect = NSRect(x: lastPoint.x - 1.4, y: lastPoint.y - 1.4, width: 2.8, height: 2.8)
            let dot = NSBezierPath(ovalIn: dotRect)
            strokeColor.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = isTemplate
        return image
    }

}

/// Renders sparklines and duplex graphs. Draws from the model's series, which changes only per sample.
@MainActor
struct GraphWidget: WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage {
        let series = model.series ?? WidgetSeries()
        switch model.layout {
        case .cpuSparkline:
            return MenuBarIconRenderer.drawCPUSparkline(
                history: series.primary,
                userHistory: series.secondary,
                systemHistory: series.tertiary,
                label: model.label,
                colorRole: model.colorRole
            )
        case .duplexGraph:
            if model.category == .network {
                return MenuBarIconRenderer.drawNetworkSplitDuplexGraph(
                    inHistory: series.primary,
                    outHistory: series.secondary,
                    label: model.label,
                    colorRole: model.colorRole
                )
            }
            return MenuBarIconRenderer.drawDiskSplitDuplexGraph(
                readHistory: series.primary,
                writeHistory: series.secondary,
                label: model.label,
                colorRole: model.colorRole
            )
        default:
            let color = WidgetColor.resolve(model.colorRole, category: model.category)
            return MenuBarIconRenderer.drawColoredSparkline(
                values: series.primary,
                maxValue: series.primaryMax,
                strokeColor: color,
                fillColor: color.withAlphaComponent(0.25),
                label: model.label,
                isTemplate: model.prefersTemplate
            )
        }
    }
}
