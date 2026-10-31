import SwiftUI
import iStatsCore

/// Pure mathematical and layout helpers for TrendChart scaling, stats, and scrub interaction.
public enum TrendChartMath {
    public struct Stats: Equatable, Sendable {
        public let min: Double
        public let avg: Double
        public let max: Double
        public let now: Double

        public init(min: Double, avg: Double, max: Double, now: Double) {
            self.min = min
            self.avg = avg
            self.max = max
            self.now = now
        }
    }

    /// Computes summary statistics (Min, Avg, Max, Now) across a scalar series.
    public static func computeStats(for values: [Double]) -> Stats? {
        guard let first = values.first, !values.isEmpty else { return nil }
        var minVal = first
        var maxVal = first
        var sum = 0.0
        for v in values {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
            sum += v
        }
        let avgVal = sum / Double(values.count)
        let nowVal = values.last ?? first
        return Stats(min: minVal, avg: avgVal, max: maxVal, now: nowVal)
    }

    /// Resolves the nearest sample index from a continuous horizontal hover position.
    public static func hoverIndex(for xPosition: CGFloat, totalWidth: CGFloat, count: Int) -> Int? {
        guard count > 0, totalWidth > 0 else { return nil }
        let fraction = Swift.max(0.0, Swift.min(1.0, Double(xPosition / totalWidth)))
        let index = Int(round(fraction * Double(count - 1)))
        return Swift.max(0, Swift.min(count - 1, index))
    }

    /// Formats relative time elapsed from sample index and interval.
    public static func formatRelativeTime(secondsAgo: Double) -> String {
        let sec = Swift.max(0, Int(round(secondsAgo)))
        if sec < 60 {
            return "\(sec)s ago"
        } else if sec < 3600 {
            let mins = sec / 60
            let rem = sec % 60
            return rem > 0 ? "\(mins)m \(rem)s ago" : "\(mins)m ago"
        } else {
            return "\(sec / 3600)h ago"
        }
    }

    /// Computes an auto-scaling upper ceiling boundary with decay floor.
    public static func computeMaxBound(values: [Double], fixedMax: Double? = nil, floor: Double = 1.0) -> Double {
        if let fm = fixedMax, fm > 0 { return fm }
        let observed = values.max() ?? 0.0
        return Swift.max(observed * 1.15, floor)
    }
}

/// Rendering modes supported by the unified `TrendChart`.
public enum TrendChartMode {
    case single(values: [Double], color: Color, fillGradient: Bool = true)
    case stacked(primary: [Double], secondary: [Double], primaryColor: Color, secondaryColor: Color)
    case mirrored(top: [Double], bottom: [Double], topColor: Color, bottomColor: Color, topLabel: String = "↓", bottomLabel: String = "↑")
}

/// A unified, responsive vector sparkline and history trend chart with hover scrubbing and statistics.
public struct TrendChart: View {
    public let mode: TrendChartMode
    public var fixedMax: Double?
    public var height: CGFloat
    public var sampleIntervalSeconds: Double
    public var showStatsStrip: Bool
    public var formatter: (Double) -> String

    @State private var hoverLocation: CGPoint?
    @State private var hoveredSampleIndex: Int?

    public init(
        mode: TrendChartMode,
        fixedMax: Double? = nil,
        height: CGFloat = 60,
        sampleIntervalSeconds: Double = 1.0,
        showStatsStrip: Bool = false,
        formatter: @escaping (Double) -> String = { String(format: "%.1f", $0) }
    ) {
        self.mode = mode
        self.fixedMax = fixedMax
        self.height = height
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.showStatsStrip = showStatsStrip
        self.formatter = formatter
    }

    public var body: some View {
        VStack(spacing: 4) {
            // Hover Header Overlay
            if let index = hoveredSampleIndex, let hoverInfo = computeHoverText(for: index) {
                HStack {
                    Text(hoverInfo.timeString)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hoverInfo.valueString)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 2)
                .transition(.opacity)
            }

            // Vector Chart Canvas
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .leading) {
                    // Background Subtle Grid Lines
                    VStack(spacing: 0) {
                        Divider().opacity(0.15)
                        Spacer()
                        Divider().opacity(0.15)
                        Spacer()
                        Divider().opacity(0.15)
                    }

                    // Render Chart Lines & Fills
                    switch mode {
                    case let .single(values, color, fillGradient):
                        renderSingle(values: values, color: color, fillGradient: fillGradient, in: size)
                    case let .stacked(primary, secondary, primaryColor, secondaryColor):
                        renderStacked(primary: primary, secondary: secondary, primaryColor: primaryColor, secondaryColor: secondaryColor, in: size)
                    case let .mirrored(top, bottom, topColor, bottomColor, _, _):
                        renderMirrored(top: top, bottom: bottom, topColor: topColor, bottomColor: bottomColor, in: size)
                    }

                    // Scrubber Hairline
                    if let location = hoverLocation, let index = hoveredSampleIndex {
                        let count = sampleCount
                        if count > 1 {
                            let xPos = (CGFloat(index) / CGFloat(count - 1)) * size.width
                            Path { p in
                                p.move(to: CGPoint(x: xPos, y: 0))
                                p.addLine(to: CGPoint(x: xPos, y: size.height))
                            }
                            .stroke(Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                            Circle()
                                .fill(Color.primary)
                                .frame(width: 5, height: 5)
                                .position(x: xPos, y: location.y)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location
                        hoveredSampleIndex = TrendChartMath.hoverIndex(
                            for: location.x,
                            totalWidth: size.width,
                            count: sampleCount
                        )
                    case .ended:
                        hoverLocation = nil
                        hoveredSampleIndex = nil
                    }
                }
            }
            .frame(height: height)
            .cardBackground(cornerRadius: 6)

            // Optional Stats Strip
            if showStatsStrip, let stats = primaryStats {
                HStack(spacing: Tokens.md) {
                    statLabel(title: "Min", value: stats.min)
                    statLabel(title: "Avg", value: stats.avg)
                    statLabel(title: "Max", value: stats.max)
                    statLabel(title: "Now", value: stats.now)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Subview Rendering

    @ViewBuilder
    private func renderSingle(values: [Double], color: Color, fillGradient: Bool, in size: CGSize) -> some View {
        let maxBound = TrendChartMath.computeMaxBound(values: values, fixedMax: fixedMax)
        let points = normalizePoints(values, maxBound: maxBound, in: size)

        if points.count >= 2 {
            if fillGradient {
                Path { p in
                    p.move(to: CGPoint(x: points[0].x, y: size.height))
                    for pt in points { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.35), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            Path { p in
                p.move(to: points[0])
                for pt in points.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func renderStacked(primary: [Double], secondary: [Double], primaryColor: Color, secondaryColor: Color, in size: CGSize) -> some View {
        let count = Swift.min(primary.count, secondary.count)
        let totals = (0..<count).map { primary[$0] + secondary[$0] }
        let maxBound = TrendChartMath.computeMaxBound(values: totals, fixedMax: fixedMax)

        let totalPoints = normalizePoints(totals, maxBound: maxBound, in: size)
        let primaryPoints = normalizePoints(primary, maxBound: maxBound, in: size)

        if totalPoints.count >= 2 {
            // Secondary (top portion) fill
            Path { p in
                p.move(to: CGPoint(x: totalPoints[0].x, y: size.height))
                for pt in totalPoints { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: totalPoints.last!.x, y: size.height))
                p.closeSubpath()
            }
            .fill(secondaryColor.opacity(0.3))

            // Primary (base portion) fill
            Path { p in
                p.move(to: CGPoint(x: primaryPoints[0].x, y: size.height))
                for pt in primaryPoints { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: primaryPoints.last!.x, y: size.height))
                p.closeSubpath()
            }
            .fill(primaryColor.opacity(0.45))

            // Total stroke
            Path { p in
                p.move(to: totalPoints[0])
                for pt in totalPoints.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(secondaryColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Primary stroke
            Path { p in
                p.move(to: primaryPoints[0])
                for pt in primaryPoints.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(primaryColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func renderMirrored(top: [Double], bottom: [Double], topColor: Color, bottomColor: Color, in size: CGSize) -> some View {
        let maxTop = TrendChartMath.computeMaxBound(values: top, fixedMax: fixedMax)
        let maxBottom = TrendChartMath.computeMaxBound(values: bottom, fixedMax: fixedMax)
        let globalMax = Swift.max(maxTop, maxBottom)

        let midY = size.height / 2.0
        let topPoints = normalizeMirrored(top, maxBound: globalMax, baseY: midY, isTop: true, in: size)
        let bottomPoints = normalizeMirrored(bottom, maxBound: globalMax, baseY: midY, isTop: false, in: size)

        // Midline
        Path { p in
            p.move(to: CGPoint(x: 0, y: midY))
            p.addLine(to: CGPoint(x: size.width, y: midY))
        }
        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)

        if topPoints.count >= 2 {
            Path { p in
                p.move(to: CGPoint(x: topPoints[0].x, y: midY))
                for pt in topPoints { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: topPoints.last!.x, y: midY))
                p.closeSubpath()
            }
            .fill(topColor.opacity(0.3))

            Path { p in
                p.move(to: topPoints[0])
                for pt in topPoints.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(topColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        if bottomPoints.count >= 2 {
            Path { p in
                p.move(to: CGPoint(x: bottomPoints[0].x, y: midY))
                for pt in bottomPoints { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: bottomPoints.last!.x, y: midY))
                p.closeSubpath()
            }
            .fill(bottomColor.opacity(0.3))

            Path { p in
                p.move(to: bottomPoints[0])
                for pt in bottomPoints.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(bottomColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Helpers

    private var sampleCount: Int {
        switch mode {
        case .single(let vals, _, _): return vals.count
        case .stacked(let p, let s, _, _): return Swift.min(p.count, s.count)
        case .mirrored(let t, let b, _, _, _, _): return Swift.min(t.count, b.count)
        }
    }

    private var primaryStats: TrendChartMath.Stats? {
        switch mode {
        case .single(let vals, _, _): return TrendChartMath.computeStats(for: vals)
        case .stacked(let p, let s, _, _):
            let count = Swift.min(p.count, s.count)
            return TrendChartMath.computeStats(for: (0..<count).map { p[$0] + s[$0] })
        case .mirrored(let t, let b, _, _, _, _):
            let count = Swift.min(t.count, b.count)
            return TrendChartMath.computeStats(for: (0..<count).map { t[$0] + b[$0] })
        }
    }

    private func statLabel(title: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.secondary)
            Text(formatter(value))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func computeHoverText(for index: Int) -> (timeString: String, valueString: String)? {
        let count = sampleCount
        guard index >= 0, index < count else { return nil }
        let secAgo = Double(count - 1 - index) * sampleIntervalSeconds
        let timeStr = TrendChartMath.formatRelativeTime(secondsAgo: secAgo)

        switch mode {
        case .single(let vals, _, _):
            return (timeStr, formatter(vals[index]))
        case .stacked(let p, let s, _, _):
            let tot = p[index] + s[index]
            return (timeStr, "\(formatter(tot)) (Apps \(formatter(p[index])) · Sys \(formatter(s[index])))")
        case .mirrored(let t, let b, _, _, let tLabel, let bLabel):
            return (timeStr, "\(tLabel) \(formatter(t[index]))  \(bLabel) \(formatter(b[index]))")
        }
    }

    private func normalizePoints(_ values: [Double], maxBound: Double, in size: CGSize) -> [CGPoint] {
        guard values.count > 1, maxBound > 0 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, val in
            let clamped = Swift.max(0.0, Swift.min(maxBound, val))
            let normY = size.height - CGFloat(clamped / maxBound) * size.height
            return CGPoint(x: CGFloat(idx) * stepX, y: normY)
        }
    }

    private func normalizeMirrored(_ values: [Double], maxBound: Double, baseY: CGFloat, isTop: Bool, in size: CGSize) -> [CGPoint] {
        guard values.count > 1, maxBound > 0 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        let halfHeight = size.height / 2.0
        return values.enumerated().map { idx, val in
            let clamped = Swift.max(0.0, Swift.min(maxBound, val))
            let offset = CGFloat(clamped / maxBound) * halfHeight
            let y = isTop ? (baseY - offset) : (baseY + offset)
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }
}

#Preview("TrendChart - Single, Stacked, Mirrored") {
    VStack(spacing: 20) {
        TrendChart(
            mode: .single(values: [10, 25, 40, 35, 60, 55, 78, 65, 80], color: .mint),
            height: 60,
            showStatsStrip: true
        )

        TrendChart(
            mode: .stacked(
                primary: [15, 20, 25, 30, 28, 35, 40],
                secondary: [5, 8, 12, 10, 15, 12, 18],
                primaryColor: .blue,
                secondaryColor: .red.opacity(0.7)
            ),
            height: 60
        )

        TrendChart(
            mode: .mirrored(
                top: [100, 350, 420, 1200, 800, 600],
                bottom: [50, 120, 80, 210, 150, 90],
                topColor: .indigo,
                bottomColor: .pink,
                topLabel: "↓",
                bottomLabel: "↑"
            ),
            height: 80,
            showStatsStrip: true
        )
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}

