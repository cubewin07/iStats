import SwiftUI
import AppKit
@preconcurrency import Accessibility
import iStatsCore

/// Band descriptor for `.banded` mode (e.g. Memory Pressure / Temperature thresholds).
public struct ChartBand: Sendable {
    public let threshold: Double
    public let color: Color
    public let label: String

    public init(threshold: Double, color: Color, label: String) {
        self.threshold = threshold
        self.color = color
        self.label = label
    }
}

/// Rendering modes for the hero `LiveChart` (ADR 0009 / Task 8.4).
public enum LiveChartMode {
    case single(values: [Double], color: Color, deepColor: Color? = nil, fixedMax: Double? = nil)
    case stacked(primary: [Double], secondary: [Double], primaryColor: Color, secondaryColor: Color, fixedMax: Double? = nil)
    case mirrored(top: [Double], bottom: [Double], topColor: Color, bottomColor: Color, topLabel: String = "↓", bottomLabel: String = "↑", fixedMax: Double? = nil)
    case banded(values: [Double], bands: [ChartBand], fixedMax: Double? = nil)

    public var valuesForStats: [Double] {
        switch self {
        case .single(let vals, _, _, _):
            return vals
        case .stacked(let p, let s, _, _, _):
            return zip(p, s).map(+)
        case .mirrored(let top, let bot, _, _, _, _, _):
            return zip(top, bot).map(+)
        case .banded(let vals, _, _):
            return vals
        }
    }

    public var primaryValues: [Double] {
        switch self {
        case .single(let vals, _, _, _): return vals
        case .stacked(let p, _, _, _, _): return p
        case .mirrored(let top, _, _, _, _, _, _): return top
        case .banded(let vals, _, _): return vals
        }
    }

    public var primaryColor: Color {
        switch self {
        case .single(_, let c, _, _): return c
        case .stacked(_, _, let p, _, _): return p
        case .mirrored(_, _, let top, _, _, _, _): return top
        case .banded(_, let bands, _): return bands.first?.color ?? .accentColor
        }
    }

    public var deepColor: Color {
        switch self {
        case .single(_, let c, let d, _): return d ?? c
        case .stacked(_, _, let p, _, _): return p
        case .mirrored(_, _, let top, _, _, _, _): return top
        case .banded(_, let bands, _): return bands.first?.color ?? .accentColor
        }
    }
}

/// Full-bleed, gliding, interactive hero chart for Instrument panels (ADR 0009 / Task 8.4).
public struct LiveChart: View {
    @Environment(\.motionPolicy) private var motionPolicy

    public let mode: LiveChartMode
    public var category: MetricCategory
    public var height: CGFloat
    public var sampleIntervalSeconds: Double
    public var showAverageLine: Bool
    public var showPeakMarker: Bool
    public var onScrub: ((_ index: Int?, _ value: Double?, _ secondsAgo: Double?) -> Void)?

    @State private var hoverLocation: CGPoint?
    @State private var hoveredIndex: Int?
    @State private var lastHapticPeakFiredIndex: Int?
    @State private var pulseScale: CGFloat = 1.0
    @State private var lastSampleTimestamp: Date = Date()

    public init(
        category: MetricCategory,
        mode: LiveChartMode,
        height: CGFloat = 84,
        sampleIntervalSeconds: Double = 1.0,
        showAverageLine: Bool = false,
        showPeakMarker: Bool = false,
        onScrub: ((_ index: Int?, _ value: Double?, _ secondsAgo: Double?) -> Void)? = nil
    ) {
        self.category = category
        self.mode = mode
        self.height = height
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.showAverageLine = showAverageLine
        self.showPeakMarker = showPeakMarker
        self.onScrub = onScrub
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let chartHeight = proxy.size.height

            ZStack(alignment: .topLeading) {
                if motionPolicy == .full {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(lastSampleTimestamp)
                        let offsetFraction = LiveChartMath.glideOffset(elapsed: elapsed, interval: sampleIntervalSeconds)
                        canvasContent(width: width, height: chartHeight, glideFraction: offsetFraction)
                    }
                } else {
                    canvasContent(width: width, height: chartHeight, glideFraction: 0.0)
                }

                // Interactive Crosshair & Scrub Lens
                if let hover = hoverLocation, let index = hoveredIndex {
                    crosshairOverlay(x: hover.x, index: index, width: width, height: chartHeight)
                }
            }
            .mask(
                // Leading 12 pt fade-in mask + bottom fade into surface
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 12)

                    Rectangle()
                        .fill(Color.black)
                }
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                handleHover(phase: phase, width: width)
            }
            .background(
                Button("") {
                    copyScrubbedValue()
                }
                .keyboardShortcut("c", modifiers: .command)
                .opacity(0.001)
                .allowsHitTesting(false)
            )
        }
        .frame(height: height)
        .accessibilityChartDescriptor(self)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.rawValue.capitalized) chart")
        .accessibilityValue(accessibilitySummary)
        .onChange(of: mode.primaryValues) { _ in
            lastSampleTimestamp = Date()
        }
    }

    // MARK: - Canvas Rendering

    @ViewBuilder
    private func canvasContent(width: CGFloat, height: CGFloat, glideFraction: Double) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            switch mode {
            case .single(let values, let color, let deep, let fixedMax):
                let maxBound = LiveChartMath.computeMaxBound(values: values, fixedMax: fixedMax)
                drawSingleSeries(
                    context: &context,
                    values: values,
                    color: color,
                    deepColor: deep ?? color,
                    maxBound: maxBound,
                    width: w,
                    height: h,
                    glide: glideFraction
                )

            case .stacked(let primary, let secondary, let pColor, let sColor, let fixedMax):
                let totals = zip(primary, secondary).map(+)
                let maxBound = LiveChartMath.computeMaxBound(values: totals, fixedMax: fixedMax)
                drawStackedSeries(
                    context: &context,
                    primary: primary,
                    secondary: secondary,
                    primaryColor: pColor,
                    secondaryColor: sColor,
                    maxBound: maxBound,
                    width: w,
                    height: h,
                    glide: glideFraction
                )

            case .mirrored(let top, let bot, let topColor, let botColor, _, _, let fixedMax):
                let combinedMax = max(top.max() ?? 0.0, bot.max() ?? 0.0)
                let maxBound = LiveChartMath.computeMaxBound(values: [combinedMax], fixedMax: fixedMax)
                drawMirroredSeries(
                    context: &context,
                    top: top,
                    bottom: bot,
                    topColor: topColor,
                    bottomColor: botColor,
                    maxBound: maxBound,
                    width: w,
                    height: h,
                    glide: glideFraction
                )

            case .banded(let values, let bands, let fixedMax):
                let maxBound = LiveChartMath.computeMaxBound(values: values, fixedMax: fixedMax)
                drawBandedSeries(
                    context: &context,
                    values: values,
                    bands: bands,
                    maxBound: maxBound,
                    width: w,
                    height: h,
                    glide: glideFraction
                )
            }
        }
    }

    // MARK: - Series Renderers

    private func drawSingleSeries(
        context: inout GraphicsContext,
        values: [Double],
        color: Color,
        deepColor: Color,
        maxBound: Double,
        width: CGFloat,
        height: CGFloat,
        glide: Double
    ) {
        guard values.count >= 2, maxBound > 0 else { return }

        let n = values.count
        let dx = width / CGFloat(max(1, n - 1))
        let glideShift = (motionPolicy == .full ? CGFloat(glide) * dx : 0.0)

        // Convert values to screen points
        let points: [LiveChartMath.Point2D] = values.enumerated().map { i, v in
            let x = CGFloat(i) * dx + glideShift
            let yFraction = CGFloat(max(0.0, min(maxBound, v)) / maxBound)
            let y = height * (1.0 - yFraction)
            return LiveChartMath.Point2D(x: Double(x), y: Double(y))
        }

        let segments = LiveChartMath.smoothSegments(points: points)

        // 1. Fill Path (Gradient tint 32% -> deep 8% -> clear)
        var fillPath = Path()
        if let first = segments.first {
            fillPath.move(to: CGPoint(x: first.start.x, y: height))
            fillPath.addLine(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in segments {
                fillPath.addCurve(
                    to: CGPoint(x: seg.end.x, y: seg.end.y),
                    control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                    control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
                )
            }
            if let last = segments.last {
                fillPath.addLine(to: CGPoint(x: last.end.x, y: height))
            }
            fillPath.closeSubpath()

            let fillGradient = Gradient(colors: [
                color.opacity(0.32),
                deepColor.opacity(0.08),
                Color.clear
            ])
            context.fill(
                fillPath,
                with: .linearGradient(
                    fillGradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: height)
                )
            )
        }

        // 2. Stroke Path (1.5 pt tint)
        var strokePath = Path()
        if let first = segments.first {
            strokePath.move(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in segments {
                strokePath.addCurve(
                    to: CGPoint(x: seg.end.x, y: seg.end.y),
                    control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                    control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
                )
            }
            context.stroke(
                strokePath,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }

        // 3. Optional Average line
        if showAverageLine, let stats = LiveChartMath.computeStats(for: values) {
            let avgY = height * CGFloat(1.0 - (stats.avg / maxBound))
            var avgPath = Path()
            avgPath.move(to: CGPoint(x: 0, y: avgY))
            avgPath.addLine(to: CGPoint(x: width, y: avgY))
            context.stroke(
                avgPath,
                with: .color(color.opacity(0.4)),
                style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
            )
        }

        // 4. Optional Peak marker ▲
        if showPeakMarker, let peakIdx = LiveChartMath.peakIndex(values: values), peakIdx < points.count {
            let peakPoint = points[peakIdx]
            let markerRect = CGRect(x: peakPoint.x - 4, y: peakPoint.y - 10, width: 8, height: 6)
            var peakPath = Path()
            peakPath.move(to: CGPoint(x: markerRect.midX, y: markerRect.minY))
            peakPath.addLine(to: CGPoint(x: markerRect.maxX, y: markerRect.maxY))
            peakPath.addLine(to: CGPoint(x: markerRect.minX, y: markerRect.maxY))
            peakPath.closeSubpath()
            context.fill(peakPath, with: .color(color))
        }

        // 5. Live Head Dot (5 pt with pulse ring)
        if let lastPoint = points.last {
            let dotRect = CGRect(x: lastPoint.x - 2.5, y: lastPoint.y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))

            // Outer pulse ring
            let ringRect = CGRect(x: lastPoint.x - 5.5, y: lastPoint.y - 5.5, width: 11, height: 11)
            context.stroke(Path(ellipseIn: ringRect), with: .color(color.opacity(0.3)), lineWidth: 1.0)
        }
    }

    private func drawStackedSeries(
        context: inout GraphicsContext,
        primary: [Double],
        secondary: [Double],
        primaryColor: Color,
        secondaryColor: Color,
        maxBound: Double,
        width: CGFloat,
        height: CGFloat,
        glide: Double
    ) {
        let n = min(primary.count, secondary.count)
        guard n >= 2, maxBound > 0 else { return }

        let dx = width / CGFloat(max(1, n - 1))
        let glideShift = (motionPolicy == .full ? CGFloat(glide) * dx : 0.0)

        let totals = zip(primary, secondary).map(+)
        let totalPoints: [LiveChartMath.Point2D] = totals.enumerated().map { i, v in
            let x = CGFloat(i) * dx + glideShift
            let yFraction = CGFloat(max(0.0, min(maxBound, v)) / maxBound)
            let y = height * (1.0 - yFraction)
            return LiveChartMath.Point2D(x: Double(x), y: Double(y))
        }

        let primaryPoints: [LiveChartMath.Point2D] = primary.enumerated().map { i, v in
            let x = CGFloat(i) * dx + glideShift
            let yFraction = CGFloat(max(0.0, min(maxBound, v)) / maxBound)
            let y = height * (1.0 - yFraction)
            return LiveChartMath.Point2D(x: Double(x), y: Double(y))
        }

        let totalSegments = LiveChartMath.smoothSegments(points: totalPoints)
        let primarySegments = LiveChartMath.smoothSegments(points: primaryPoints)

        // Fill secondary (total to primary)
        var totalFill = Path()
        if let first = totalSegments.first {
            totalFill.move(to: CGPoint(x: first.start.x, y: height))
            totalFill.addLine(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in totalSegments {
                totalFill.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            if let last = totalSegments.last {
                totalFill.addLine(to: CGPoint(x: last.end.x, y: height))
            }
            totalFill.closeSubpath()
            context.fill(totalFill, with: .color(secondaryColor.opacity(0.24)))
        }

        // Fill primary (primary to bottom)
        var primaryFill = Path()
        if let first = primarySegments.first {
            primaryFill.move(to: CGPoint(x: first.start.x, y: height))
            primaryFill.addLine(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in primarySegments {
                primaryFill.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            if let last = primarySegments.last {
                primaryFill.addLine(to: CGPoint(x: last.end.x, y: height))
            }
            primaryFill.closeSubpath()
            context.fill(primaryFill, with: .color(primaryColor.opacity(0.35)))
        }

        // Stroke primary line
        var pStroke = Path()
        if let first = primarySegments.first {
            pStroke.move(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in primarySegments {
                pStroke.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            context.stroke(pStroke, with: .color(primaryColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        // Stroke total line
        var tStroke = Path()
        if let first = totalSegments.first {
            tStroke.move(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in totalSegments {
                tStroke.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            context.stroke(tStroke, with: .color(secondaryColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawMirroredSeries(
        context: inout GraphicsContext,
        top: [Double],
        bottom: [Double],
        topColor: Color,
        bottomColor: Color,
        maxBound: Double,
        width: CGFloat,
        height: CGFloat,
        glide: Double
    ) {
        let n = min(top.count, bottom.count)
        guard n >= 2, maxBound > 0 else { return }

        let midY = height / 2.0
        let halfHeight = height / 2.0
        let dx = width / CGFloat(max(1, n - 1))
        let glideShift = (motionPolicy == .full ? CGFloat(glide) * dx : 0.0)

        // Top points (grow upwards from midY)
        let topPoints: [LiveChartMath.Point2D] = top.enumerated().map { i, v in
            let x = CGFloat(i) * dx + glideShift
            let yFraction = CGFloat(max(0.0, min(maxBound, v)) / maxBound)
            let y = midY - (halfHeight * yFraction)
            return LiveChartMath.Point2D(x: Double(x), y: Double(y))
        }

        // Bottom points (grow downwards from midY)
        let bottomPoints: [LiveChartMath.Point2D] = bottom.enumerated().map { i, v in
            let x = CGFloat(i) * dx + glideShift
            let yFraction = CGFloat(max(0.0, min(maxBound, v)) / maxBound)
            let y = midY + (halfHeight * yFraction)
            return LiveChartMath.Point2D(x: Double(x), y: Double(y))
        }

        let topSegments = LiveChartMath.smoothSegments(points: topPoints)
        let bottomSegments = LiveChartMath.smoothSegments(points: bottomPoints)

        // Midline separator
        var midLine = Path()
        midLine.move(to: CGPoint(x: 0, y: midY))
        midLine.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(midLine, with: .color(Color.primary.opacity(0.12)), lineWidth: 0.5)

        // Top fill and stroke
        var topFill = Path()
        if let first = topSegments.first {
            topFill.move(to: CGPoint(x: first.start.x, y: midY))
            topFill.addLine(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in topSegments {
                topFill.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            if let last = topSegments.last {
                topFill.addLine(to: CGPoint(x: last.end.x, y: midY))
            }
            topFill.closeSubpath()
            context.fill(topFill, with: .color(topColor.opacity(0.24)))
        }

        var topStroke = Path()
        if let first = topSegments.first {
            topStroke.move(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in topSegments {
                topStroke.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            context.stroke(topStroke, with: .color(topColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        // Bottom fill and stroke
        var botFill = Path()
        if let first = bottomSegments.first {
            botFill.move(to: CGPoint(x: first.start.x, y: midY))
            botFill.addLine(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in bottomSegments {
                botFill.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            if let last = bottomSegments.last {
                botFill.addLine(to: CGPoint(x: last.end.x, y: midY))
            }
            botFill.closeSubpath()
            context.fill(botFill, with: .color(bottomColor.opacity(0.24)))
        }

        var botStroke = Path()
        if let first = bottomSegments.first {
            botStroke.move(to: CGPoint(x: first.start.x, y: first.start.y))
            for seg in bottomSegments {
                botStroke.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
            }
            context.stroke(botStroke, with: .color(bottomColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawBandedSeries(
        context: inout GraphicsContext,
        values: [Double],
        bands: [ChartBand],
        maxBound: Double,
        width: CGFloat,
        height: CGFloat,
        glide: Double
    ) {
        guard values.count >= 2, maxBound > 0 else { return }

        // Draw horizontal band threshold zones
        for band in bands {
            let yFraction = CGFloat(max(0.0, min(maxBound, band.threshold)) / maxBound)
            let y = height * (1.0 - yFraction)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: width, y: y))
            context.stroke(line, with: .color(band.color.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        }

        let primaryColor = bands.last?.color ?? .accentColor
        drawSingleSeries(
            context: &context,
            values: values,
            color: primaryColor,
            deepColor: primaryColor,
            maxBound: maxBound,
            width: width,
            height: height,
            glide: glide
        )
    }

    // MARK: - Interaction & Crosshair Lens

    @ViewBuilder
    private func crosshairOverlay(x: CGFloat, index: Int, width: CGFloat, height: CGFloat) -> some View {
        let values = mode.primaryValues
        if index < values.count {
            let val = values[index]
            let maxBound = LiveChartMath.computeMaxBound(values: values)
            let yFrac = CGFloat(max(0.0, min(maxBound, val)) / max(maxBound, 0.001))
            let pointY = height * (1.0 - yFrac)
            let color = mode.primaryColor

            ZStack(alignment: .topLeading) {
                // Vertical crosshair hair line
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 1, height: height)
                    .position(x: x, y: height / 2.0)

                // Snapped Dot on Curve
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .position(x: x, y: pointY)
            }
        }
    }

    private func handleHover(phase: HoverPhase, width: CGFloat) {
        switch phase {
        case .active(let loc):
            hoverLocation = loc
            let values = mode.primaryValues
            guard !values.isEmpty else { return }
            let idx = LiveChartMath.hoverIndex(for: Double(loc.x), totalWidth: Double(width), count: values.count)
            hoveredIndex = idx

            if let idx = idx, idx < values.count {
                let val = values[idx]
                let secondsAgo = Double(values.count - 1 - idx) * sampleIntervalSeconds
                onScrub?(idx, val, secondsAgo)

                // Haptic feedback on peak
                let peak = LiveChartMath.peakIndex(values: values)
                if idx == peak && lastHapticPeakFiredIndex != idx {
                    lastHapticPeakFiredIndex = idx
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } else if idx != peak {
                    lastHapticPeakFiredIndex = nil
                }
            }

        case .ended:
            hoverLocation = nil
            hoveredIndex = nil
            lastHapticPeakFiredIndex = nil
            onScrub?(nil, nil, nil)
        }
    }

    private func copyScrubbedValue() {
        let values = mode.primaryValues
        guard let idx = hoveredIndex, idx < values.count else { return }
        let val = values[idx]
        let formatted = String(format: "%.1f", val)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        let values = mode.valuesForStats
        guard let stats = LiveChartMath.computeStats(for: values) else {
            return "No data available"
        }
        return String(format: "Now: %.1f, Min: %.1f, Avg: %.1f, Max: %.1f across %d samples", stats.now, stats.min, stats.avg, stats.max, values.count)
    }
}

// MARK: - AXChartDescriptorRepresentable (Audio Graph)

extension LiveChart: AXChartDescriptorRepresentable {
    nonisolated public func makeChartDescriptor() -> AXChartDescriptor {
        MainActor.assumeIsolated {
            let values = mode.valuesForStats
            let stats = LiveChartMath.computeStats(for: values)
            let minVal = stats?.min ?? 0.0
            let maxVal = stats?.max ?? 100.0

            let xAxis = AXNumericDataAxisDescriptor(
                title: "Time",
                range: 0.0...Double(max(1, values.count)),
                gridlinePositions: []
            ) { value in "\(Int(value))s" }

            let yAxis = AXNumericDataAxisDescriptor(
                title: category.rawValue.capitalized,
                range: minVal...max(maxVal, minVal + 1.0),
                gridlinePositions: []
            ) { value in String(format: "%.1f", value) }

            let dataPoints = values.enumerated().map { i, v in
                AXDataPoint(x: Double(i), y: v)
            }

            let series = AXDataSeriesDescriptor(
                name: category.rawValue.capitalized,
                isContinuous: true,
                dataPoints: dataPoints
            )

            return AXChartDescriptor(
                title: "\(category.rawValue.capitalized) Trend",
                summary: accessibilitySummary,
                xAxis: xAxis,
                yAxis: yAxis,
                additionalAxes: [],
                series: [series]
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
struct LiveChart_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Flat series
            LiveChart(
                category: .cpu,
                mode: .single(values: Array(repeating: 25.0, count: 60), color: .blue),
                showAverageLine: true
            )

            // Spiky series
            LiveChart(
                category: .network,
                mode: .single(values: (0..<60).map { _ in Double.random(in: 10...95) }, color: .teal),
                showPeakMarker: true
            )

            // Stacked
            LiveChart(
                category: .cpu,
                mode: .stacked(
                    primary: (0..<40).map { _ in Double.random(in: 10...40) },
                    secondary: (0..<40).map { _ in Double.random(in: 5...30) },
                    primaryColor: .blue,
                    secondaryColor: .cyan
                )
            )

            // Mirrored
            LiveChart(
                category: .network,
                mode: .mirrored(
                    top: (0..<40).map { _ in Double.random(in: 5...60) },
                    bottom: (0..<40).map { _ in Double.random(in: 5...40) },
                    topColor: .blue,
                    bottomColor: .purple
                )
            )
        }
        .padding()
        .frame(width: 340)
        .background(Color.black.opacity(0.8))
    }
}
#endif
