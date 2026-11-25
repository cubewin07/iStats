import AppKit
import CoreText
import SwiftUI
import iStatsCore

extension MenuBarIconRenderer {
    public static func drawThermometerGlyph(
        fraction: Int?,
        formattedTemp: String,
        status: StatusLevel,
        minWidth: CGFloat = 42.0,
        worstCase: String? = nil
    ) -> NSImage {

        let statusColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : CategoryPalette.nsColor(for: .thermal)
        let valColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : NSColor.labelColor
        let valAttr = formatCompactValueAttributedString(value: formattedTemp, color: valColor)
        let valSize = valAttr.size()
        let valX: CGFloat = 12.0
        let worstWidth = worstCase.map { formatCompactValueAttributedString(value: $0, color: valColor).size().width } ?? 0.0
        let canvasWidth = max(minWidth, ceil(valX + max(valSize.width, worstWidth) + 2.0))
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let centerX: CGFloat = 6.0
            let bulbCenterY: CGFloat = 6.0
            let bulbRadius: CGFloat = 3.0
            let stemWidth: CGFloat = 2.4
            let stemTop: CGFloat = 17.5
            let stemBottom: CGFloat = bulbCenterY + 1.5

            let stemRect = NSRect(x: centerX - stemWidth / 2.0, y: stemBottom, width: stemWidth, height: stemTop - stemBottom)
            let stemPath = NSBezierPath(roundedRect: stemRect, xRadius: stemWidth / 2.0, yRadius: stemWidth / 2.0)
            let bulbRect = NSRect(x: centerX - bulbRadius, y: bulbCenterY - bulbRadius, width: bulbRadius * 2.0, height: bulbRadius * 2.0)
            let bulbPath = NSBezierPath(ovalIn: bulbRect)

            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
            stemPath.fill()
            bulbPath.fill()

            statusColor.setFill()
            bulbPath.fill()

            if let f = fraction {
                let clamped = min(max(Double(f) / 100.0, 0.0), 1.0)
                let fillH = max(CGFloat(clamped) * (stemTop - stemBottom), 1.0)
                let fillRect = NSRect(x: centerX - (stemWidth - 0.4) / 2.0, y: stemBottom - 1.0, width: stemWidth - 0.4, height: fillH + 1.0)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: (stemWidth - 0.4) / 2.0, yRadius: (stemWidth - 0.4) / 2.0)
                fillPath.fill()
            }

            let valY = floor((bounds.height - valSize.height) / 2.0) - 1.0
            valAttr.draw(at: NSPoint(x: valX, y: valY))

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawFanGlyph(
        text rpmStr: String,
        isFanless: Bool = false,
        status: StatusLevel
    ) -> NSImage {
        let fixedWidth: CGFloat = 44.0
        let size = NSSize(width: fixedWidth, height: 22)
        let iconColor = isFanless
            ? NSColor.secondaryLabelColor.withAlphaComponent(0.50)
            : ((status >= .warning) ? CategoryPalette.statusNSColor(for: status) : CategoryPalette.nsColor(for: .fan))
        let valColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : NSColor.labelColor

        let image = NSImage(size: size, flipped: false) { bounds in
            if let sfSymbol = NSImage(systemSymbolName: "fan", accessibilityDescription: nil) {
                let symConfig = NSImage.SymbolConfiguration(pointSize: 10.0, weight: .bold)
                if let configured = sfSymbol.withSymbolConfiguration(symConfig) {
                    let iconRect = NSRect(x: 2.0, y: (bounds.height - 11.0) / 2.0, width: 11.0, height: 11.0)
                    iconColor.set()
                    configured.draw(in: iconRect)
                }
            }

            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: valColor
            ]
            let str = NSAttributedString(string: rpmStr, attributes: attrs)
            let strSize = str.size()
            let textX = max(15.0, bounds.maxX - 2.0 - strSize.width)
            let textY = (bounds.height - strSize.height) / 2.0
            str.draw(at: NSPoint(x: textX, y: textY))

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws authentic iStat Menus horizontal Battery Instrument with live proportional level fill & multi-state overlays.
    public static func drawBatteryInstrument(
        charge: Double?,
        state: BatteryState?,
        hasBattery: Bool,
        variant: PowerStateVariant? = nil
    ) -> NSImage {
        let activeVariant = variant ?? PowerStateVariant.resolve(charge: charge, state: state, hasBattery: hasBattery)
        let size = NSSize(width: 25, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            if hasBattery && activeVariant != .acDesktop {
                let roundedCharge = round(charge ?? 0.0)
                let isCritical = activeVariant == .lowBattery && roundedCharge <= 10.0

                // Battery Body Frame
                let bodyRect = NSRect(x: 1.0, y: 2.0, width: 19.5, height: 12.0)
                let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.5, yRadius: 2.5)
                body.lineWidth = 1.2
                if isCritical {
                    CategoryPalette.statusNSColor(for: .critical).setStroke()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                }
                body.stroke()

                // Battery Terminal Cap
                let capRect = NSRect(x: 21.0, y: 5.5, width: 2.0, height: 5.0)
                let cap = NSBezierPath(roundedRect: capRect, xRadius: 1.0, yRadius: 1.0)
                if isCritical {
                    CategoryPalette.statusNSColor(for: .critical).setFill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.85).setFill()
                }
                cap.fill()

                if let chg = charge {
                    let clamped = min(max(chg, 0.0), 100.0)
                    let maxFillWidth: CGFloat = 15.5
                    let fillWidth = max(maxFillWidth * CGFloat(clamped / 100.0), 1.5)
                    let fillRect = NSRect(x: 3.0, y: 4.0, width: fillWidth, height: 8.0)
                    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2)

                    let fillColor: NSColor
                    switch activeVariant {
                    case .lowBattery:
                        fillColor = CategoryPalette.statusNSColor(for: .critical)
                    case .powerDeficit:
                        fillColor = CategoryPalette.statusNSColor(for: .warning)
                    case .onHold:
                        fillColor = CategoryPalette.statusNSColor(for: .fine)
                    case .charging, .charged:
                        fillColor = CategoryPalette.statusNSColor(for: .fine)
                    case .discharging:
                        let qClamped = round(clamped)
                        fillColor = qClamped <= 20.0 ? CategoryPalette.statusNSColor(for: .critical) : (qClamped <= 40.0 ? CategoryPalette.statusNSColor(for: .elevated) : CategoryPalette.statusNSColor(for: .fine))
                    case .acDesktop, .unavailable:
                        fillColor = CategoryPalette.statusNSColor(for: .fine)
                    }
                    fillColor.setFill()
                    fillPath.fill()

                    // Multi-State Overlay Badges
                    switch activeVariant {
                    case .charging:
                        let bolt = NSBezierPath()
                        bolt.move(to: NSPoint(x: 11.5, y: 13.0))
                        bolt.line(to: NSPoint(x: 8.0, y: 8.0))
                        bolt.line(to: NSPoint(x: 10.8, y: 8.0))
                        bolt.line(to: NSPoint(x: 9.5, y: 3.0))
                        bolt.line(to: NSPoint(x: 14.0, y: 9.0))
                        bolt.line(to: NSPoint(x: 11.2, y: 9.0))
                        bolt.close()
                        CategoryPalette.statusNSColor(for: .elevated).setFill()
                        bolt.fill()
                        bolt.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.6).setStroke()
                        bolt.stroke()

                    case .onHold:
                        let p1 = NSBezierPath(roundedRect: NSRect(x: 8.8, y: 5.0, width: 1.8, height: 6.0), xRadius: 0.9, yRadius: 0.9)
                        let p2 = NSBezierPath(roundedRect: NSRect(x: 11.8, y: 5.0, width: 1.8, height: 6.0), xRadius: 0.9, yRadius: 0.9)
                        CategoryPalette.statusNSColor(for: .warning).setFill()
                        p1.fill()
                        p2.fill()
                        p1.lineWidth = 0.5
                        p2.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.65).setStroke()
                        p1.stroke()
                        p2.stroke()

                    case .powerDeficit:
                        let bolt = NSBezierPath()
                        bolt.move(to: NSPoint(x: 9.0, y: 12.8))
                        bolt.line(to: NSPoint(x: 6.6, y: 8.2))
                        bolt.line(to: NSPoint(x: 8.8, y: 8.2))
                        bolt.line(to: NSPoint(x: 7.6, y: 3.2))
                        bolt.line(to: NSPoint(x: 11.0, y: 8.8))
                        bolt.line(to: NSPoint(x: 8.8, y: 8.8))
                        bolt.close()
                        CategoryPalette.statusNSColor(for: .warning).setFill()
                        bolt.fill()
                        bolt.lineWidth = 0.4
                        NSColor.black.withAlphaComponent(0.65).setStroke()
                        bolt.stroke()

                        let arrow = NSBezierPath()
                        arrow.move(to: NSPoint(x: 13.5, y: 11.8))
                        arrow.line(to: NSPoint(x: 13.5, y: 4.8))
                        arrow.move(to: NSPoint(x: 11.5, y: 6.8))
                        arrow.line(to: NSPoint(x: 13.5, y: 4.2))
                        arrow.line(to: NSPoint(x: 15.5, y: 6.8))
                        arrow.lineWidth = 1.3
                        arrow.lineCapStyle = .round
                        arrow.lineJoinStyle = .round
                        NSColor.white.setStroke()
                        arrow.stroke()

                    case .lowBattery:
                        let stem = NSBezierPath(roundedRect: NSRect(x: 9.8, y: 6.8, width: 2.0, height: 4.8), xRadius: 1.0, yRadius: 1.0)
                        let dot = NSBezierPath(ovalIn: NSRect(x: 9.8, y: 4.0, width: 2.0, height: 2.0))
                        NSColor.white.setFill()
                        stem.fill()
                        dot.fill()
                        stem.lineWidth = 0.5
                        dot.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.7).setStroke()
                        stem.stroke()
                        dot.stroke()

                    case .charged:
                        let prong1 = NSBezierPath(rect: NSRect(x: 7.0, y: 6.0, width: 2.2, height: 1.2))
                        let prong2 = NSBezierPath(rect: NSRect(x: 7.0, y: 8.8, width: 2.2, height: 1.2))
                        let plugBody = NSBezierPath(roundedRect: NSRect(x: 9.2, y: 5.0, width: 4.2, height: 6.0), xRadius: 1.0, yRadius: 1.0)
                        let stub = NSBezierPath(rect: NSRect(x: 13.4, y: 7.2, width: 1.6, height: 1.6))
                        NSColor.white.setFill()
                        prong1.fill()
                        prong2.fill()
                        plugBody.fill()
                        stub.fill()
                        plugBody.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.6).setStroke()
                        plugBody.stroke()

                    case .discharging, .acDesktop, .unavailable:
                        break
                    }
                } else {
                    let dashLine = NSBezierPath()
                    dashLine.move(to: NSPoint(x: 5.0, y: 8.0))
                    dashLine.line(to: NSPoint(x: 16.0, y: 8.0))
                    let dashes: [CGFloat] = [2.0, 2.0]
                    dashLine.setLineDash(dashes, count: 2, phase: 0.0)
                    dashLine.lineWidth = 1.0
                    NSColor.secondaryLabelColor.withAlphaComponent(0.5).setStroke()
                    dashLine.stroke()
                }
            } else {
                let plug = NSBezierPath(roundedRect: NSRect(x: 5.0, y: 3.0, width: 12.0, height: 10.0), xRadius: 2.5, yRadius: 2.5)
                plug.lineWidth = 1.2
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                plug.stroke()

                let p1 = NSBezierPath(rect: NSRect(x: 17.0, y: 5.0, width: 4.0, height: 2.0))
                let p2 = NSBezierPath(rect: NSRect(x: 17.0, y: 9.0, width: 4.0, height: 2.0))
                CategoryPalette.statusNSColor(for: .fine).setFill()
                p1.fill()
                p2.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws dynamic Dual Activity Arrows (`↓` Download and `↑` Upload) with signature colors.
    public static func drawNetworkActivityArrows(inActive: Bool, outActive: Bool) -> NSImage {

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let down = NSBezierPath()
            down.move(to: NSPoint(x: 5.0, y: 15.0))
            down.line(to: NSPoint(x: 5.0, y: 4.0))
            down.move(to: NSPoint(x: 2.0, y: 7.0))
            down.line(to: NSPoint(x: 5.0, y: 3.0))
            down.line(to: NSPoint(x: 8.0, y: 7.0))
            down.lineWidth = inActive ? 2.0 : 1.3
            down.lineCapStyle = .round
            down.lineJoinStyle = .round
            (inActive ? CategoryPalette.nsColor(for: .network) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            down.stroke()

            let up = NSBezierPath()
            up.move(to: NSPoint(x: 13.0, y: 3.0))
            up.line(to: NSPoint(x: 13.0, y: 14.0))
            up.move(to: NSPoint(x: 10.0, y: 11.0))
            up.line(to: NSPoint(x: 13.0, y: 15.0))
            up.line(to: NSPoint(x: 16.0, y: 11.0))
            up.lineWidth = outActive ? 2.0 : 1.3
            up.lineCapStyle = .round
            up.lineJoinStyle = .round
            (outActive ? NSColor(CategoryPalette.Series.networkUpload) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            up.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws dynamic Disk Read / Write Activity LEDs (`R` and `W`) with signature colors.
    public static func drawDiskActivityLeds(readActive rActive: Bool, writeActive wActive: Bool) -> NSImage {

        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let font = NSFont.systemFont(ofSize: 9.5, weight: .black)

            let rBadge = NSBezierPath(roundedRect: NSRect(x: 1.0, y: 2.0, width: 8.5, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            if rActive {
                CategoryPalette.nsColor(for: .disk).setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                ("R" as NSString).draw(at: NSPoint(x: 2.2, y: 3.0), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("R" as NSString).draw(at: NSPoint(x: 2.2, y: 3.0), withAttributes: attrs)
            }

            let wBadge = NSBezierPath(roundedRect: NSRect(x: 10.5, y: 2.0, width: 8.5, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            if wActive {
                NSColor(CategoryPalette.Series.diskWrite).setFill()
                wBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                ("W" as NSString).draw(at: NSPoint(x: 11.0, y: 3.0), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                wBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("W" as NSString).draw(at: NSPoint(x: 11.0, y: 3.0), withAttributes: attrs)
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawGPUDieSymbol(utilization: Double? = nil, tempCelsius: Double? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let util = min(max(utilization ?? 0.0, 0.0), 100.0)

            let frameRect = NSRect(x: center.x - 7.0, y: center.y - 7.0, width: 14.0, height: 14.0)
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 2.5, yRadius: 2.5)

            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            framePath.fill()

            framePath.lineWidth = 1.0
            NSColor.labelColor.withAlphaComponent(0.40).setStroke()
            framePath.stroke()

            let pinLength: CGFloat = 1.0
            let pinColor = NSColor.secondaryLabelColor.withAlphaComponent(0.50)
            pinColor.setStroke()

            for py in [center.y - 3.5, center.y + 3.5] {
                let lPin = NSBezierPath()
                lPin.move(to: NSPoint(x: frameRect.minX - pinLength, y: py))
                lPin.line(to: NSPoint(x: frameRect.minX, y: py))
                lPin.lineWidth = 0.8
                lPin.stroke()

                let rPin = NSBezierPath()
                rPin.move(to: NSPoint(x: frameRect.maxX, y: py))
                rPin.line(to: NSPoint(x: frameRect.maxX + pinLength, y: py))
                rPin.lineWidth = 0.8
                rPin.stroke()
            }

            let dieRect = NSRect(x: center.x - 5.0, y: center.y - 5.0, width: 10.0, height: 10.0)
            let dieClip = NSBezierPath(roundedRect: dieRect, xRadius: 1.5, yRadius: 1.5)

            NSGraphicsContext.saveGraphicsState()
            dieClip.addClip()

            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            dieClip.fill()

            let col = CategoryPalette.nsColor(for: .gpu)
            if util > 0 {
                let fillH = max(dieRect.height * CGFloat(util / 100.0), 1.5)
                let fillRect = NSRect(x: dieRect.minX, y: dieRect.minY, width: dieRect.width, height: fillH)
                col.setFill()
                fillRect.fill()
            }

            let gridPath = NSBezierPath()
            gridPath.move(to: NSPoint(x: center.x, y: dieRect.minY))
            gridPath.line(to: NSPoint(x: center.x, y: dieRect.maxY))
            gridPath.move(to: NSPoint(x: dieRect.minX, y: center.y))
            gridPath.line(to: NSPoint(x: dieRect.maxX, y: center.y))
            gridPath.lineWidth = 0.5
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            gridPath.stroke()

            NSGraphicsContext.restoreGraphicsState()

            dieClip.lineWidth = 0.8
            col.withAlphaComponent(0.60).setStroke()
            dieClip.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawMemoryPressureBadge(pressure: MemoryPressure?) -> NSImage {
        let p = pressure ?? .normal
        let cacheKey = "memPressure:\(p.rawValue)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)

            let pillRect = NSRect(x: center.x - 7.0, y: center.y - 8.0, width: 14.0, height: 16.0)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3.5, yRadius: 3.5)
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()

            let barW: CGFloat = 8.5
            let barH: CGFloat = 2.8
            let barX: CGFloat = center.x - barW / 2.0

            let levels: [(y: CGFloat, active: Bool)] = [
                (center.y - 5.5, true),
                (center.y - 1.4, p == .warning || p == .critical),
                (center.y + 2.7, p == .critical)
            ]

            let fillCol: NSColor = (p == .critical) ? CategoryPalette.statusNSColor(for: .critical) : ((p == .warning) ? CategoryPalette.statusNSColor(for: .elevated) : CategoryPalette.statusNSColor(for: .fine))

            for lvl in levels {
                let rect = NSRect(x: barX, y: lvl.y, width: barW, height: barH)
                let bPath = NSBezierPath(roundedRect: rect, xRadius: 1.0, yRadius: 1.0)
                if lvl.active {
                    fillCol.setFill()
                    bPath.fill()
                } else {
                    NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                    bPath.fill()
                }
            }

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

}

/// Renders glyph widgets: thermometer, fan, battery, network arrows and disk LEDs.
@MainActor
struct GlyphWidget: WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage {
        switch model.layout {
        case .thermometer:
            return MenuBarIconRenderer.drawThermometerGlyph(
                fraction: model.flags.first == true ? model.fractions.first : nil,
                formattedTemp: model.texts.first ?? "--°",
                status: model.status,
                minWidth: WidgetMetrics.width(model.widthClass)
            )
        case .fanGlyph:
            return MenuBarIconRenderer.drawFanGlyph(
                text: model.texts.first ?? "--",
                isFanless: model.flags.first == true,
                status: model.status
            )
        case .arrows:
            return MenuBarIconRenderer.drawNetworkActivityArrows(inActive: model.flags[0], outActive: model.flags[1])
        case .leds:
            return MenuBarIconRenderer.drawDiskActivityLeds(readActive: model.flags[0], writeActive: model.flags[1])
        default:
            return MenuBarIconRenderer.drawBatteryInstrument(
                charge: model.flags.first == true ? Double(model.fractions.first ?? 0) : nil,
                state: nil,
                hasBattery: model.flags.count > 1 ? model.flags[1] : true,
                variant: model.variant
            )
        }
    }
}
