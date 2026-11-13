import SwiftUI
import AppKit
@preconcurrency import Accessibility
import iStatsCore

/// Band descriptor for `.banded` mode (e.g. Memory Pressure / Temperature thresholds).
public struct ChartBand: Sendable, Equatable {
    public let threshold: Double
    public let color: Color
    public let label: String

    public init(threshold: Double, color: Color, label: String) {
        self.threshold = threshold
        self.color = color
        self.label = label
    }
}

/// Rendering modes for the hero and history `LiveChart` (ADR 0010 / Task 8.5.3).
///
/// Supports timestamped series (`[ChartPoint]`, `[DualChartPoint]`) and time-aligned
/// min/max/mean envelopes (`[BucketPoint]`), while preserving backward-compatible
/// `[Double]` convenience factories for existing call sites and previews.
public struct LiveChartMode: Sendable {
    internal enum Payload: Sendable {
        case single(points: [ChartPoint], color: Color, deepColor: Color, domainFloor: Double?, fixedMax: Double?, isTimestamped: Bool)
        case stacked(points: [DualChartPoint], primaryColor: Color, secondaryColor: Color, domainFloor: Double?, fixedMax: Double?, isTimestamped: Bool)
        case mirrored(points: [DualChartPoint], topColor: Color, bottomColor: Color, topLabel: String, bottomLabel: String, domainFloor: Double?, fixedMax: Double?, isTimestamped: Bool)
        case banded(points: [ChartPoint], bands: [ChartBand], domainFloor: Double?, fixedMax: Double?, isTimestamped: Bool)
        case envelope(buckets: [BucketPoint], color: Color, deepColor: Color, bands: [ChartBand], domainFloor: Double?, fixedMax: Double?)
        case mirroredEnvelope(top: [BucketPoint], bottom: [BucketPoint], topColor: Color, bottomColor: Color, topLabel: String, bottomLabel: String, domainFloor: Double?, fixedMax: Double?)
    }

    internal let payload: Payload

    private init(_ payload: Payload) {
        self.payload = payload
    }

    // MARK: - Time-Domain Factories

    public static func single(
        points: [ChartPoint],
        color: Color,
        deepColor: Color? = nil,
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        LiveChartMode(.single(
            points: points,
            color: color,
            deepColor: deepColor ?? color,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: true
        ))
    }

    public static func stacked(
        points: [DualChartPoint],
        primaryColor: Color,
        secondaryColor: Color,
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        LiveChartMode(.stacked(
            points: points,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: true
        ))
    }

    public static func mirrored(
        points: [DualChartPoint],
        topColor: Color,
        bottomColor: Color,
        topLabel: String = "↓",
        bottomLabel: String = "↑",
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        LiveChartMode(.mirrored(
            points: points,
            topColor: topColor,
            bottomColor: bottomColor,
            topLabel: topLabel,
            bottomLabel: bottomLabel,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: true
        ))
    }

    public static func banded(
        points: [ChartPoint],
        bands: [ChartBand],
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        LiveChartMode(.banded(
            points: points,
            bands: bands,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: true
        ))
    }

    public static func envelope(
        buckets: [BucketPoint],
        color: Color,
        deepColor: Color? = nil,
        bands: [ChartBand] = [],
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        LiveChartMode(.envelope(
            buckets: buckets,
            color: color,
            deepColor: deepColor ?? color,
            bands: bands,
            domainFloor: domainFloor,
            fixedMax: fixedMax
        ))
    }

    public static func mirroredEnvelope(
        top: [BucketPoint],
        bottom: [BucketPoint],
        topColor: Color,
        bottomColor: Color,
        topLabel: String = "↓",
        bottomLabel: String = "↑",
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        LiveChartMode(.mirroredEnvelope(
            top: top,
            bottom: bottom,
            topColor: topColor,
            bottomColor: bottomColor,
            topLabel: topLabel,
            bottomLabel: bottomLabel,
            domainFloor: domainFloor,
            fixedMax: fixedMax
        ))
    }

    // MARK: - Backward-Compatible [Double] Convenience Factories

    public static func single(
        values: [Double],
        color: Color,
        deepColor: Color? = nil,
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        let points = Self.synthesizePoints(values: values)
        return LiveChartMode(.single(
            points: points,
            color: color,
            deepColor: deepColor ?? color,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: false
        ))
    }

    public static func stacked(
        primary: [Double],
        secondary: [Double],
        primaryColor: Color,
        secondaryColor: Color,
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        let points = Self.synthesizeDualPoints(primary: primary, secondary: secondary)
        return LiveChartMode(.stacked(
            points: points,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: false
        ))
    }

    public static func mirrored(
        top: [Double],
        bottom: [Double],
        topColor: Color,
        bottomColor: Color,
        topLabel: String = "↓",
        bottomLabel: String = "↑",
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        let points = Self.synthesizeDualPoints(primary: top, secondary: bottom)
        return LiveChartMode(.mirrored(
            points: points,
            topColor: topColor,
            bottomColor: bottomColor,
            topLabel: topLabel,
            bottomLabel: bottomLabel,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: false
        ))
    }

    public static func banded(
        values: [Double],
        bands: [ChartBand],
        domainFloor: Double? = nil,
        fixedMax: Double? = nil
    ) -> LiveChartMode {
        let points = Self.synthesizePoints(values: values)
        return LiveChartMode(.banded(
            points: points,
            bands: bands,
            domainFloor: domainFloor,
            fixedMax: fixedMax,
            isTimestamped: false
        ))
    }

    private static func synthesizePoints(values: [Double]) -> [ChartPoint] {
        let count = values.count
        guard count > 0 else { return [] }
        return values.enumerated().map { idx, val in
            ChartPoint(timestamp: Double(idx - (count - 1)), value: val)
        }
    }

    private static func synthesizeDualPoints(primary: [Double], secondary: [Double]) -> [DualChartPoint] {
        let count = min(primary.count, secondary.count)
        guard count > 0 else { return [] }
        return (0..<count).map { idx in
            DualChartPoint(
                timestamp: Double(idx - (count - 1)),
                primary: primary[idx],
                secondary: secondary[idx]
            )
        }
    }

    // MARK: - Introspection

    public var isTimestamped: Bool {
        switch payload {
        case .single(_, _, _, _, _, let ts),
             .stacked(_, _, _, _, _, let ts),
             .mirrored(_, _, _, _, _, _, _, let ts),
             .banded(_, _, _, _, let ts):
            return ts
        case .envelope, .mirroredEnvelope:
            return true
        }
    }

    public var isEnvelope: Bool {
        switch payload {
        case .envelope, .mirroredEnvelope:
            return true
        default:
            return false
        }
    }

    public var isMirrored: Bool {
        switch payload {
        case .mirrored, .mirroredEnvelope:
            return true
        default:
            return false
        }
    }

    public var latestTimestamp: TimeInterval? {
        guard isTimestamped else { return nil }
        switch payload {
        case .single(let pts, _, _, _, _, _),
             .banded(let pts, _, _, _, _):
            return pts.map(\.timestamp).max()
        case .stacked(let pts, _, _, _, _, _),
             .mirrored(let pts, _, _, _, _, _, _, _):
            return pts.map(\.timestamp).max()
        case .envelope(let buckets, _, _, _, _, _):
            return buckets.map(\.timestamp).max()
        case .mirroredEnvelope(let top, let bottom, _, _, _, _, _, _):
            let topMax = top.map(\.timestamp).max()
            let botMax = bottom.map(\.timestamp).max()
            switch (topMax, botMax) {
            case (.some(let a), .some(let b)): return max(a, b)
            case (.some(let a), .none): return a
            case (.none, .some(let b)): return b
            case (.none, .none): return nil
            }
        }
    }

    public var valuesForStats: [Double] {
        switch payload {
        case .single(let pts, _, _, _, _, _),
             .banded(let pts, _, _, _, _):
            return pts.map(\.value)
        case .stacked(let pts, _, _, _, _, _),
             .mirrored(let pts, _, _, _, _, _, _, _):
            return pts.map { $0.primary + $0.secondary }
        case .envelope(let buckets, _, _, _, _, _):
            return buckets.map(\.mean)
        case .mirroredEnvelope(let top, let bottom, _, _, _, _, _, _):
            return zip(top, bottom).map { $0.mean + $1.mean }
        }
    }

    public var primaryValues: [Double] {
        switch payload {
        case .single(let pts, _, _, _, _, _),
             .banded(let pts, _, _, _, _):
            return pts.map(\.value)
        case .stacked(let pts, _, _, _, _, _),
             .mirrored(let pts, _, _, _, _, _, _, _):
            return pts.map(\.primary)
        case .envelope(let buckets, _, _, _, _, _):
            return buckets.map(\.mean)
        case .mirroredEnvelope(let top, _, _, _, _, _, _, _):
            return top.map(\.mean)
        }
    }

    public var primaryColor: Color {
        switch payload {
        case .single(_, let c, _, _, _, _): return c
        case .stacked(_, let p, _, _, _, _): return p
        case .mirrored(_, let top, _, _, _, _, _, _): return top
        case .banded(_, let bands, _, _, _): return bands.first?.color ?? .accentColor
        case .envelope(_, let c, _, let bands, _, _): return bands.first?.color ?? c
        case .mirroredEnvelope(_, _, let top, _, _, _, _, _): return top
        }
    }

    public var deepColor: Color {
        switch payload {
        case .single(_, _, let d, _, _, _): return d
        case .stacked(_, let p, _, _, _, _): return p
        case .mirrored(_, let top, _, _, _, _, _, _): return top
        case .banded(_, let bands, _, _, _): return bands.first?.color ?? .accentColor
        case .envelope(_, _, let d, let bands, _, _): return bands.first?.color ?? d
        case .mirroredEnvelope(_, _, let top, _, _, _, _, _): return top
        }
    }

    public var domainFloor: Double? {
        switch payload {
        case .single(_, _, _, let f, _, _),
             .stacked(_, _, _, let f, _, _),
             .mirrored(_, _, _, _, _, let f, _, _),
             .banded(_, _, let f, _, _),
             .envelope(_, _, _, _, let f, _),
             .mirroredEnvelope(_, _, _, _, _, _, let f, _):
            return f
        }
    }

    public var fixedMax: Double? {
        switch payload {
        case .single(_, _, _, _, let m, _),
             .stacked(_, _, _, _, let m, _),
             .mirrored(_, _, _, _, _, _, let m, _),
             .banded(_, _, _, let m, _),
             .envelope(_, _, _, _, _, let m),
             .mirroredEnvelope(_, _, _, _, _, _, _, let m):
            return m
        }
    }
}

// MARK: - ChartModel (Time-Domain Timeline & Scale Hysteresis)

/// Maintains per-chart `ChartTimeline` and `ChartScaleState` across frames without triggering
/// outer SwiftUI view-body invalidations on every `TimelineView` tick.
@MainActor
final class ChartModel: ObservableObject {
    private(set) var timeline: ChartTimeline
    private(set) var topScale: ChartScaleState
    private(set) var bottomScale: ChartScaleState

    private var lastFrameDate: TimeInterval?
    private var synthesizedLatestTimestamp: TimeInterval?
    private var lastLegacySignature: LegacySignature?

    private struct LegacySignature: Equatable {
        let count: Int
        let first: Double?
        let last: Double?
        let sum: Double
    }

    struct ResolvedSeries {
        let primaryPoints: [ChartPoint]
        let secondaryPoints: [ChartPoint]
        let totalPoints: [ChartPoint]
        let primaryBuckets: [BucketPoint]
        let secondaryBuckets: [BucketPoint]
        let windowDuration: TimeInterval
        let latestTimestamp: TimeInterval?
    }

    init(sampleInterval: TimeInterval = 1.0) {
        self.timeline = ChartTimeline(sampleInterval: sampleInterval)
        self.topScale = ChartScaleState()
        self.bottomScale = ChartScaleState()
    }

    /// Resolves timestamps, advances `ChartTimeline`, and updates `topScale`/`bottomScale`.
    @discardableResult
    func step(
        now: TimeInterval,
        mode: LiveChartMode,
        category: MetricCategory,
        sampleInterval: TimeInterval,
        explicitWindow: TimeInterval?,
        isScrubbing: Bool,
        motionPolicy: MotionPolicy
    ) -> ResolvedSeries {
        let dt: TimeInterval
        if let prev = lastFrameDate {
            dt = max(0.0, min(0.5, now - prev))
        } else {
            dt = 0.0
        }
        lastFrameDate = now

        let effectiveInterval = max(1e-3, sampleInterval)
        if abs(timeline.sampleInterval - effectiveInterval) > 1e-6 {
            let currentEdge = timeline.edge
            let hadEdge = currentEdge != 0.0
            timeline = ChartTimeline(
                edge: hadEdge ? currentEdge : nil,
                frozenEdge: timeline.frozenEdge,
                sampleInterval: effectiveInterval
            )
        }

        let resolved = resolveSeries(
            mode: mode,
            now: now,
            sampleInterval: effectiveInterval,
            explicitWindow: explicitWindow
        )

        if let latestTs = resolved.latestTimestamp {
            let timelineNow: TimeInterval
            let timelineDt: TimeInterval
            if mode.isEnvelope {
                // Envelopes use epoch center timestamps; keep the active right-hand bucket visible.
                timelineNow = max(now, latestTs + effectiveInterval)
                timelineDt = motionPolicy == .full ? dt : 10.0
            } else if motionPolicy != .full {
                timelineNow = max(now, latestTs + effectiveInterval)
                timelineDt = 10.0
            } else {
                timelineNow = now
                timelineDt = dt
            }

            timeline.step(
                now: timelineNow,
                latestTimestamp: latestTs,
                dt: timelineDt,
                isScrubbing: isScrubbing
            )
        }

        let scaleDt = (motionPolicy == .full && !isScrubbing) ? dt : 10.0
        updateScales(
            resolved: resolved,
            mode: mode,
            category: category,
            dt: scaleDt
        )

        return resolved
    }

    func resolveSeries(
        mode: LiveChartMode,
        now: TimeInterval,
        sampleInterval: TimeInterval,
        explicitWindow: TimeInterval?
    ) -> ResolvedSeries {
        switch mode.payload {
        case .single(let pts, _, _, _, _, let isTimestamped),
             .banded(let pts, _, _, _, let isTimestamped):
            let normalized = isTimestamped
                ? Self.sortChronologically(pts, timestamp: \.timestamp)
                : synthesizeLegacySingle(pts, now: now, interval: sampleInterval)
            let window = resolveWindow(explicit: explicitWindow, points: normalized, buckets: [], interval: sampleInterval, isTimestamped: isTimestamped)
            return ResolvedSeries(
                primaryPoints: normalized,
                secondaryPoints: [],
                totalPoints: normalized,
                primaryBuckets: [],
                secondaryBuckets: [],
                windowDuration: window,
                latestTimestamp: normalized.last?.timestamp
            )

        case .stacked(let pts, _, _, _, _, let isTimestamped):
            let orderedDual = isTimestamped
                ? Self.sortChronologically(pts, timestamp: \.timestamp)
                : synthesizeLegacyDual(pts, now: now, interval: sampleInterval)
            let primary = orderedDual.map { ChartPoint(timestamp: $0.timestamp, value: $0.primary) }
            let secondary = orderedDual.map { ChartPoint(timestamp: $0.timestamp, value: $0.secondary) }
            let total = orderedDual.map { ChartPoint(timestamp: $0.timestamp, value: $0.primary + $0.secondary) }
            let window = resolveWindow(explicit: explicitWindow, points: primary, buckets: [], interval: sampleInterval, isTimestamped: isTimestamped)
            return ResolvedSeries(
                primaryPoints: primary,
                secondaryPoints: secondary,
                totalPoints: total,
                primaryBuckets: [],
                secondaryBuckets: [],
                windowDuration: window,
                latestTimestamp: primary.last?.timestamp
            )

        case .mirrored(let pts, _, _, _, _, _, _, let isTimestamped):
            let orderedDual = isTimestamped
                ? Self.sortChronologically(pts, timestamp: \.timestamp)
                : synthesizeLegacyDual(pts, now: now, interval: sampleInterval)
            let top = orderedDual.map { ChartPoint(timestamp: $0.timestamp, value: $0.primary) }
            let bot = orderedDual.map { ChartPoint(timestamp: $0.timestamp, value: $0.secondary) }
            let window = resolveWindow(explicit: explicitWindow, points: top, buckets: [], interval: sampleInterval, isTimestamped: isTimestamped)
            return ResolvedSeries(
                primaryPoints: top,
                secondaryPoints: bot,
                totalPoints: top,
                primaryBuckets: [],
                secondaryBuckets: [],
                windowDuration: window,
                latestTimestamp: top.last?.timestamp
            )

        case .envelope(let buckets, _, _, _, _, _):
            let ordered = Self.sortChronologically(buckets, timestamp: \.timestamp)
            let meanPoints = ordered.map { ChartPoint(timestamp: $0.timestamp, value: $0.mean) }
            let window = resolveWindow(explicit: explicitWindow, points: meanPoints, buckets: ordered, interval: sampleInterval, isTimestamped: true)
            return ResolvedSeries(
                primaryPoints: meanPoints,
                secondaryPoints: [],
                totalPoints: meanPoints,
                primaryBuckets: ordered,
                secondaryBuckets: [],
                windowDuration: window,
                latestTimestamp: ordered.last?.timestamp
            )

        case .mirroredEnvelope(let top, let bottom, _, _, _, _, _, _):
            let orderedTop = Self.sortChronologically(top, timestamp: \.timestamp)
            let orderedBot = Self.sortChronologically(bottom, timestamp: \.timestamp)
            let topMeans = orderedTop.map { ChartPoint(timestamp: $0.timestamp, value: $0.mean) }
            let botMeans = orderedBot.map { ChartPoint(timestamp: $0.timestamp, value: $0.mean) }
            let combinedBuckets = orderedTop.isEmpty ? orderedBot : orderedTop
            let window = resolveWindow(explicit: explicitWindow, points: topMeans, buckets: combinedBuckets, interval: sampleInterval, isTimestamped: true)
            let latest = [orderedTop.last?.timestamp, orderedBot.last?.timestamp].compactMap { $0 }.max()
            return ResolvedSeries(
                primaryPoints: topMeans,
                secondaryPoints: botMeans,
                totalPoints: topMeans,
                primaryBuckets: orderedTop,
                secondaryBuckets: orderedBot,
                windowDuration: window,
                latestTimestamp: latest
            )
        }
    }

    private func legacyAnchor(for values: [Double], now: TimeInterval, interval: TimeInterval) -> TimeInterval {
        let sig = LegacySignature(
            count: values.count,
            first: values.first,
            last: values.last,
            sum: values.reduce(0.0, +)
        )
        if sig != lastLegacySignature || synthesizedLatestTimestamp == nil {
            lastLegacySignature = sig
            if let prev = synthesizedLatestTimestamp {
                synthesizedLatestTimestamp = max(now, prev + interval * 0.25)
            } else {
                synthesizedLatestTimestamp = now
            }
        }
        return synthesizedLatestTimestamp ?? now
    }

    private func synthesizeLegacySingle(_ offsetPoints: [ChartPoint], now: TimeInterval, interval: TimeInterval) -> [ChartPoint] {
        guard !offsetPoints.isEmpty else { return [] }
        let anchor = legacyAnchor(for: offsetPoints.map(\.value), now: now, interval: interval)
        let count = offsetPoints.count
        return offsetPoints.enumerated().map { idx, pt in
            ChartPoint(timestamp: anchor - Double(count - 1 - idx) * interval, value: pt.value)
        }
    }

    private func synthesizeLegacyDual(_ offsetPoints: [DualChartPoint], now: TimeInterval, interval: TimeInterval) -> [DualChartPoint] {
        guard !offsetPoints.isEmpty else { return [] }
        let anchor = legacyAnchor(for: offsetPoints.map { $0.primary + $0.secondary }, now: now, interval: interval)
        let count = offsetPoints.count
        return offsetPoints.enumerated().map { idx, pt in
            DualChartPoint(
                timestamp: anchor - Double(count - 1 - idx) * interval,
                primary: pt.primary,
                secondary: pt.secondary
            )
        }
    }

    private func resolveWindow(
        explicit: TimeInterval?,
        points: [ChartPoint],
        buckets: [BucketPoint],
        interval: TimeInterval,
        isTimestamped: Bool
    ) -> TimeInterval {
        if let explicit, explicit.isFinite, explicit > 0.0 {
            return explicit
        }
        if !buckets.isEmpty {
            let deltas = zip(buckets, buckets.dropFirst()).map { $1.timestamp - $0.timestamp }.filter { $0 > 0.01 }
            let bucketWidth = deltas.min() ?? 2.5
            if bucketWidth >= 6.0 { return 900.0 }
            if bucketWidth >= 2.0 { return 300.0 }
            return max(60.0, Double(max(buckets.count, 1)) * bucketWidth)
        }
        if !isTimestamped && interval > 1.5 {
            return max(60.0, Double(max(points.count - 1, 1)) * interval)
        }
        return max(60.0, 60.0 * interval)
    }

    private func updateScales(
        resolved: ResolvedSeries,
        mode: LiveChartMode,
        category: MetricCategory,
        dt: TimeInterval
    ) {
        let startEdge = timeline.edge - resolved.windowDuration
        let endEdge = timeline.edge + max(1.0, timeline.sampleInterval)

        switch mode.payload {
        case .mirrored:
            let visibleTop = visibleSlice(resolved.primaryPoints, start: startEdge, end: endEdge)
            let visibleBot = visibleSlice(resolved.secondaryPoints, start: startEdge, end: endEdge)
            let topMax = visibleTop.map(\.value).max() ?? 0.0
            let botMax = visibleBot.map(\.value).max() ?? 0.0

            topScale.update(
                visibleMax: topMax,
                visibleMin: 0.0,
                category: category,
                fixedFloor: mode.domainFloor ?? 0.0,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )
            bottomScale.update(
                visibleMax: botMax,
                visibleMin: 0.0,
                category: category,
                fixedFloor: mode.domainFloor ?? 0.0,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )

        case .mirroredEnvelope:
            let visibleTop = visibleBucketSlice(resolved.primaryBuckets, start: startEdge, end: endEdge)
            let visibleBot = visibleBucketSlice(resolved.secondaryBuckets, start: startEdge, end: endEdge)
            let topMax = visibleTop.map(\.max).max() ?? 0.0
            let botMax = visibleBot.map(\.max).max() ?? 0.0

            topScale.update(
                visibleMax: topMax,
                visibleMin: 0.0,
                category: category,
                fixedFloor: mode.domainFloor ?? 0.0,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )
            bottomScale.update(
                visibleMax: botMax,
                visibleMin: 0.0,
                category: category,
                fixedFloor: mode.domainFloor ?? 0.0,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )

        case .envelope:
            let visible = visibleBucketSlice(resolved.primaryBuckets, start: startEdge, end: endEdge)
            let maxVal = visible.map(\.max).max() ?? 0.0
            let minVal = visible.map(\.min).min() ?? 0.0
            topScale.update(
                visibleMax: maxVal,
                visibleMin: minVal,
                category: category,
                fixedFloor: mode.domainFloor,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )

        case .stacked:
            let visibleTotals = visibleSlice(resolved.totalPoints, start: startEdge, end: endEdge)
            let maxVal = visibleTotals.map(\.value).max() ?? 0.0
            topScale.update(
                visibleMax: maxVal,
                visibleMin: 0.0,
                category: category,
                fixedFloor: mode.domainFloor ?? 0.0,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )

        case .single, .banded:
            let visible = visibleSlice(resolved.primaryPoints, start: startEdge, end: endEdge)
            let maxVal = visible.map(\.value).max() ?? 0.0
            let minVal = visible.map(\.value).min() ?? 0.0
            topScale.update(
                visibleMax: maxVal,
                visibleMin: minVal,
                category: category,
                fixedFloor: mode.domainFloor,
                fixedCeiling: mode.fixedMax,
                minSpan: 1.0,
                dt: dt
            )
        }
    }

    private func visibleSlice(_ points: [ChartPoint], start: TimeInterval, end: TimeInterval) -> [ChartPoint] {
        let filtered = points.filter { $0.timestamp >= start && $0.timestamp <= end }
        return filtered.isEmpty ? points : filtered
    }

    private func visibleBucketSlice(_ buckets: [BucketPoint], start: TimeInterval, end: TimeInterval) -> [BucketPoint] {
        let filtered = buckets.filter { $0.timestamp >= start && $0.timestamp <= end }
        return filtered.isEmpty ? buckets : filtered
    }

    private static func sortChronologically<T>(_ items: [T], timestamp: (T) -> TimeInterval) -> [T] {
        if zip(items, items.dropFirst()).contains(where: { timestamp($0) > timestamp($1) }) {
            return items.sorted { timestamp($0) < timestamp($1) }
        }
        return items
    }
}

// MARK: - ChartRenderer (Unified Time-Domain Path Builder & Canvas Drawing)

/// Pure path-building and `GraphicsContext` rendering helpers for `LiveChart` v3.
enum ChartRenderer {
    struct VerticalRange {
        let floor: Double
        let ceiling: Double
        let topY: CGFloat
        let baselineY: CGFloat
        let inverted: Bool

        var span: Double {
            max(1e-6, ceiling - floor)
        }

        func yPosition(for value: Double) -> CGFloat {
            let clamped = max(floor, min(ceiling, value))
            let fraction = CGFloat((clamped - floor) / span)
            if inverted {
                return baselineY + (topY - baselineY) * fraction
            } else {
                return baselineY - (baselineY - topY) * fraction
            }
        }
    }

    struct SeriesGeometry {
        let screenPoints: [LiveChartMath.Point2D]
        let segments: [LiveChartMath.CubicSegment]
        let strokePath: Path
        let fillPath: Path
        let minCurveY: CGFloat
        let maxCurveY: CGFloat
        let headPoint: CGPoint?
    }

    struct RenderStyle {
        let color: Color
        let deepColor: Color
        let opacity: Double
        let isDashed: Bool
        let bands: [ChartBand]
        let drawAreaFill: Bool
        let colorScheme: ColorScheme
        let colorSchemeContrast: ColorSchemeContrast
    }

    /// Slices points to `[windowStart - 1 anchor, windowEnd + in-transit point]`, projects X via
    /// `ChartTimeline.xPosition`, computes Fritsch–Carlson monotone cubic segments, and constructs
    /// shared stroke/fill paths plus the interpolated live head position.
    static func buildSeriesGeometry(
        points: [ChartPoint],
        timeline: ChartTimeline,
        windowDuration: TimeInterval,
        plotWidth: CGFloat,
        verticalRange: VerticalRange
    ) -> SeriesGeometry? {
        guard !points.isEmpty, plotWidth > 0.0 else { return nil }

        let windowStart = timeline.edge - windowDuration
        let sliced = sliceWithBoundaryAnchors(points, start: windowStart, end: timeline.edge, timestamp: \.timestamp)
        guard !sliced.isEmpty else { return nil }

        let projected: [LiveChartMath.Point2D] = sliced.map { pt in
            let x = ChartTimeline.xPosition(
                for: pt.timestamp,
                edge: timeline.edge,
                width: Double(plotWidth),
                window: windowDuration
            )
            let y = Double(verticalRange.yPosition(for: pt.value))
            return LiveChartMath.Point2D(x: x, y: y)
        }

        let segments = LiveChartMath.smoothSegments(points: projected, tension: 1.0)
        let strokePath = buildStrokePath(segments: segments)
        let fillPath = buildFillPath(segments: segments, baselineY: verticalRange.baselineY)

        let ys = projected.map { CGFloat($0.y) }
        let minY = ys.min() ?? verticalRange.baselineY
        let maxY = ys.max() ?? verticalRange.baselineY

        let headTimestamp = min(timeline.edge, points.last?.timestamp ?? timeline.edge)
        let headPoint: CGPoint?
        if headTimestamp >= windowStart, let valAtEdge = timeline.value(at: headTimestamp, points: sliced) {
            let hx = CGFloat(ChartTimeline.xPosition(
                for: headTimestamp,
                edge: timeline.edge,
                width: Double(plotWidth),
                window: windowDuration
            ))
            let hy = verticalRange.yPosition(for: valAtEdge)
            headPoint = CGPoint(x: hx, y: hy)
        } else {
            headPoint = nil
        }

        return SeriesGeometry(
            screenPoints: projected,
            segments: segments,
            strokePath: strokePath,
            fillPath: fillPath,
            minCurveY: minY,
            maxCurveY: maxY,
            headPoint: headPoint
        )
    }

    /// Builds a continuous `min...max` envelope polygon across `BucketPoint`s using Fritsch–Carlson
    /// splines along `max` forward and `min` in reverse.
    static func buildEnvelopePolygon(
        buckets: [BucketPoint],
        timeline: ChartTimeline,
        windowDuration: TimeInterval,
        plotWidth: CGFloat,
        verticalRange: VerticalRange
    ) -> Path? {
        guard buckets.count >= 2, plotWidth > 0.0 else { return nil }

        let windowStart = timeline.edge - windowDuration
        let sliced = sliceWithBoundaryAnchors(buckets, start: windowStart, end: timeline.edge, timestamp: \.timestamp)
        guard sliced.count >= 2 else { return nil }

        let hasSpread = sliced.contains { ($0.max - $0.min) > 0.02 * verticalRange.span }
        guard hasSpread else { return nil }

        let upperPoints: [LiveChartMath.Point2D] = sliced.map { b in
            let x = ChartTimeline.xPosition(
                for: b.timestamp,
                edge: timeline.edge,
                width: Double(plotWidth),
                window: windowDuration
            )
            return LiveChartMath.Point2D(x: x, y: Double(verticalRange.yPosition(for: b.max)))
        }
        let lowerPoints: [LiveChartMath.Point2D] = sliced.map { b in
            let x = ChartTimeline.xPosition(
                for: b.timestamp,
                edge: timeline.edge,
                width: Double(plotWidth),
                window: windowDuration
            )
            return LiveChartMath.Point2D(x: x, y: Double(verticalRange.yPosition(for: b.min)))
        }

        let upperSegs = LiveChartMath.smoothSegments(points: upperPoints, tension: 1.0)
        let lowerSegs = LiveChartMath.smoothSegments(points: lowerPoints, tension: 1.0)
        guard let firstUpper = upperSegs.first, let lastLower = lowerSegs.last else { return nil }

        var path = Path()
        path.move(to: CGPoint(x: firstUpper.start.x, y: firstUpper.start.y))
        for seg in upperSegs {
            path.addCurve(
                to: CGPoint(x: seg.end.x, y: seg.end.y),
                control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
            )
        }
        path.addLine(to: CGPoint(x: lastLower.end.x, y: lastLower.end.y))
        for seg in lowerSegs.reversed() {
            path.addCurve(
                to: CGPoint(x: seg.start.x, y: seg.start.y),
                control1: CGPoint(x: seg.control2.x, y: seg.control2.y),
                control2: CGPoint(x: seg.control1.x, y: seg.control1.y)
            )
        }
        path.closeSubpath()
        return path
    }

    static func buildStrokePath(segments: [LiveChartMath.CubicSegment]) -> Path {
        var path = Path()
        guard let first = segments.first else { return path }
        path.move(to: CGPoint(x: first.start.x, y: first.start.y))
        for seg in segments {
            path.addCurve(
                to: CGPoint(x: seg.end.x, y: seg.end.y),
                control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
            )
        }
        return path
    }

    static func buildFillPath(segments: [LiveChartMath.CubicSegment], baselineY: CGFloat) -> Path {
        var path = Path()
        guard let first = segments.first, let last = segments.last else { return path }
        path.move(to: CGPoint(x: first.start.x, y: baselineY))
        path.addLine(to: CGPoint(x: first.start.x, y: first.start.y))
        for seg in segments {
            path.addCurve(
                to: CGPoint(x: seg.end.x, y: seg.end.y),
                control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
            )
        }
        path.addLine(to: CGPoint(x: last.end.x, y: baselineY))
        path.closeSubpath()
        return path
    }

    /// Unified series renderer drawing threshold washes, area gradient fill, dark-mode underlay bloom,
    /// and the `1.75 pt` primary stroke.
    static func drawSeries(
        context: inout GraphicsContext,
        geometry: SeriesGeometry,
        verticalRange: VerticalRange,
        plotWidth: CGFloat,
        style: RenderStyle
    ) {
        if !style.bands.isEmpty {
            drawThresholdZones(
                context: &context,
                bands: style.bands,
                verticalRange: verticalRange,
                width: plotWidth
            )
        }

        if style.drawAreaFill, !geometry.segments.isEmpty {
            let fillGradient = Gradient(colors: [
                style.color.opacity(0.20 * style.opacity),
                Color.clear
            ])

            let startY: CGFloat
            let endY: CGFloat
            if verticalRange.inverted {
                startY = geometry.maxCurveY
                let spanToBase = max(1.0, startY - verticalRange.baselineY)
                endY = startY - spanToBase * 0.85
            } else {
                startY = geometry.minCurveY
                let spanToBase = max(1.0, verticalRange.baselineY - startY)
                endY = startY + spanToBase * 0.85
            }

            context.fill(
                geometry.fillPath,
                with: .linearGradient(
                    fillGradient,
                    startPoint: CGPoint(x: 0, y: startY),
                    endPoint: CGPoint(x: 0, y: endY)
                )
            )
        }

        guard !geometry.segments.isEmpty else { return }

        let strokeShading = resolvedStrokeShading(
            bands: style.bands,
            baseColor: style.color,
            opacity: style.opacity,
            verticalRange: verticalRange
        )

        if style.colorScheme == .dark && style.colorSchemeContrast == .standard {
            let bloomShading = resolvedStrokeShading(
                bands: style.bands,
                baseColor: style.color,
                opacity: 0.16 * style.opacity,
                verticalRange: verticalRange
            )
            context.drawLayer { layerCtx in
                layerCtx.addFilter(.blur(radius: 3.0))
                layerCtx.stroke(
                    geometry.strokePath,
                    with: bloomShading,
                    style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round)
                )
            }
        }

        let strokeStyle = style.isDashed
            ? StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round, dash: [4, 3])
            : StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
        context.stroke(geometry.strokePath, with: strokeShading, style: strokeStyle)
    }

    static func drawThresholdZones(
        context: inout GraphicsContext,
        bands: [ChartBand],
        verticalRange: VerticalRange,
        width: CGFloat
    ) {
        let sorted = bands.sorted { $0.threshold < $1.threshold }
        for (idx, band) in sorted.enumerated() {
            let y = verticalRange.yPosition(for: band.threshold)
            let upperY: CGFloat
            if idx + 1 < sorted.count {
                upperY = verticalRange.yPosition(for: sorted[idx + 1].threshold)
            } else {
                upperY = verticalRange.topY
            }
            let minY = min(y, upperY)
            let maxY = max(y, upperY)
            if maxY > minY {
                let washRect = CGRect(x: 0, y: minY, width: width, height: maxY - minY)
                context.fill(Path(washRect), with: .color(band.color.opacity(0.03)))
            }

            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: width, y: y))
            context.stroke(
                line,
                with: .color(band.color.opacity(0.22)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
            )
        }
    }

    private static func resolvedStrokeShading(
        bands: [ChartBand],
        baseColor: Color,
        opacity: Double,
        verticalRange: VerticalRange
    ) -> GraphicsContext.Shading {
        guard !bands.isEmpty else {
            return .color(baseColor.opacity(opacity))
        }

        let sorted = bands.sorted { $0.threshold < $1.threshold }
        let totalHeight = max(1.0, abs(verticalRange.baselineY - verticalRange.topY))
        let topLimit = min(verticalRange.topY, verticalRange.baselineY)

        func location(for threshold: Double) -> Double {
            let y = verticalRange.yPosition(for: threshold)
            return max(0.0, min(1.0, Double((y - topLimit) / totalHeight)))
        }

        var stops: [Gradient.Stop] = []
        let topColor = sorted.last?.color ?? baseColor
        stops.append(.init(color: topColor.opacity(opacity), location: 0.0))

        for idx in sorted.indices.reversed() {
            let band = sorted[idx]
            let loc = location(for: band.threshold)
            let belowColor = (idx > 0) ? sorted[idx - 1].color : baseColor
            let epsilon = 0.015
            if loc > 0.0 && loc < 1.0 {
                stops.append(.init(color: band.color.opacity(opacity), location: max(0.0, loc - epsilon)))
                stops.append(.init(color: belowColor.opacity(opacity), location: min(1.0, loc + epsilon)))
            }
        }

        let bottomColor: Color
        if let first = sorted.first, verticalRange.floor >= first.threshold {
            bottomColor = sorted.last(where: { verticalRange.floor >= $0.threshold })?.color ?? baseColor
        } else {
            bottomColor = baseColor
        }
        stops.append(.init(color: bottomColor.opacity(opacity), location: 1.0))

        let orderedStops = stops.sorted { $0.location < $1.location }
        return .linearGradient(
            Gradient(stops: orderedStops),
            startPoint: CGPoint(x: 0, y: topLimit),
            endPoint: CGPoint(x: 0, y: topLimit + totalHeight)
        )
    }

    static func drawHeadBead(
        context: inout GraphicsContext,
        at point: CGPoint,
        color: Color,
        opacity: Double
    ) {
        let haloRect = CGRect(x: point.x - 5.0, y: point.y - 5.0, width: 10.0, height: 10.0)
        context.fill(Path(ellipseIn: haloRect), with: .color(Instrument.Surface.panel))

        let beadRect = CGRect(x: point.x - 3.0, y: point.y - 3.0, width: 6.0, height: 6.0)
        context.fill(Path(ellipseIn: beadRect), with: .color(color.opacity(opacity)))
    }

    static func drawAverageLine(
        context: inout GraphicsContext,
        points: [ChartPoint],
        verticalRange: VerticalRange,
        width: CGFloat,
        color: Color
    ) {
        let values = points.map(\.value)
        guard let stats = LiveChartMath.computeStats(for: values) else { return }
        let avgY = verticalRange.yPosition(for: stats.avg)
        var avgPath = Path()
        avgPath.move(to: CGPoint(x: 0, y: avgY))
        avgPath.addLine(to: CGPoint(x: width, y: avgY))
        context.stroke(
            avgPath,
            with: .color(color.opacity(0.4)),
            style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
        )
    }

    static func drawPeakMarker(
        context: inout GraphicsContext,
        points: [ChartPoint],
        timeline: ChartTimeline,
        windowDuration: TimeInterval,
        plotWidth: CGFloat,
        totalWidth: CGFloat,
        verticalRange: VerticalRange,
        color: Color,
        valueFormatter: ((Double) -> String)?
    ) {
        let values = points.map(\.value)
        guard let peakIdx = LiveChartMath.peakIndex(values: values), peakIdx < points.count else { return }
        let peak = points[peakIdx]
        let px = CGFloat(ChartTimeline.xPosition(
            for: peak.timestamp,
            edge: timeline.edge,
            width: Double(plotWidth),
            window: windowDuration
        ))
        guard px >= 0.0 && px <= totalWidth else { return }
        let py = verticalRange.yPosition(for: peak.value)

        let isBottom = verticalRange.inverted
        let markerRect = CGRect(x: px - 4, y: isBottom ? py + 4 : py - 10, width: 8, height: 6)
        var peakPath = Path()
        if isBottom {
            peakPath.move(to: CGPoint(x: markerRect.midX, y: markerRect.maxY))
            peakPath.addLine(to: CGPoint(x: markerRect.maxX, y: markerRect.minY))
            peakPath.addLine(to: CGPoint(x: markerRect.minX, y: markerRect.minY))
        } else {
            peakPath.move(to: CGPoint(x: markerRect.midX, y: markerRect.minY))
            peakPath.addLine(to: CGPoint(x: markerRect.maxX, y: markerRect.maxY))
            peakPath.addLine(to: CGPoint(x: markerRect.minX, y: markerRect.maxY))
        }
        peakPath.closeSubpath()
        context.fill(peakPath, with: .color(color))

        let labelText = valueFormatter?(peak.value) ?? String(format: "%.0f", peak.value)
        let isNearRight = px > totalWidth - 45
        let isNearLeft = px < 35
        let anchor: UnitPoint = isNearRight
            ? (isBottom ? .bottomTrailing : .topTrailing)
            : (isNearLeft ? (isBottom ? .bottomLeading : .topLeading) : (isBottom ? .top : .bottom))
        let labelY = isBottom ? py + 14 : max(10, py - 14)
        context.draw(
            Text(labelText)
                .font(Instrument.Typography.micro)
                .foregroundColor(color),
            at: CGPoint(x: px, y: labelY),
            anchor: anchor
        )
    }

    static func drawStandardGrid(
        context: inout GraphicsContext,
        scale: ChartScaleState,
        verticalRange: VerticalRange,
        width: CGFloat,
        valueFormatter: ((Double) -> String)?
    ) {
        let span = scale.displayedCeiling - scale.displayedFloor
        guard span > 0 else { return }
        let step = span / 3.0
        let gridTicks = [
            scale.displayedFloor + step,
            scale.displayedFloor + 2.0 * step,
            scale.displayedCeiling
        ]

        for (index, tick) in gridTicks.enumerated() {
            let rawY = verticalRange.yPosition(for: tick)
            let lineY = (index == gridTicks.count - 1) ? max(0.5, rawY) : rawY

            var gridPath = Path()
            gridPath.move(to: CGPoint(x: 0, y: lineY))
            gridPath.addLine(to: CGPoint(x: width, y: lineY))
            context.stroke(
                gridPath,
                with: .color(Color.primary.opacity(0.06)),
                style: StrokeStyle(lineWidth: 0.5)
            )

            let label = valueFormatter?(tick) ?? String(format: "%.0f", tick)
            let isTopCeiling = (index == gridTicks.count - 1) && (lineY < 12.0)
            let labelPoint = CGPoint(x: 4.0, y: isTopCeiling ? (lineY + 2.0) : (lineY - 2.0))
            let anchor: UnitPoint = isTopCeiling ? .topLeading : .bottomLeading

            context.draw(
                Text(label)
                    .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                    .foregroundColor(.secondary.opacity(0.65)),
                at: labelPoint,
                anchor: anchor
            )
        }
    }

    static func drawMirroredGridAndLabels(
        context: inout GraphicsContext,
        topScale: ChartScaleState,
        bottomScale: ChartScaleState,
        topLabel: String,
        bottomLabel: String,
        width: CGFloat,
        height: CGFloat,
        showHairlines: Bool,
        valueFormatter: ((Double) -> String)?
    ) {
        let midY = height / 2.0

        // Midline separator
        var midLine = Path()
        midLine.move(to: CGPoint(x: 0, y: midY))
        midLine.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(
            midLine,
            with: .color(Color.primary.opacity(showHairlines ? 0.08 : 0.10)),
            style: StrokeStyle(lineWidth: 0.5)
        )

        if showHairlines {
            for y in [0.5, height - 0.5] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: width, y: y))
                context.stroke(
                    line,
                    with: .color(Color.primary.opacity(0.06)),
                    style: StrokeStyle(lineWidth: 0.5)
                )
            }
        }

        guard height >= 40.0 else { return }

        let topText = "\(topLabel) \(valueFormatter?(topScale.displayedCeiling) ?? String(format: "%.0f", topScale.displayedCeiling))"
        let botText = "\(bottomLabel) \(valueFormatter?(bottomScale.displayedCeiling) ?? String(format: "%.0f", bottomScale.displayedCeiling))"
        let gutterFont = Font.system(size: 9.5, weight: .regular).monospacedDigit()

        context.draw(
            Text(topText)
                .font(gutterFont)
                .foregroundColor(.secondary.opacity(0.65)),
            at: CGPoint(x: 4.0, y: 2.0),
            anchor: .topLeading
        )
        context.draw(
            Text(botText)
                .font(gutterFont)
                .foregroundColor(.secondary.opacity(0.65)),
            at: CGPoint(x: 4.0, y: height - 2.0),
            anchor: .bottomLeading
        )
    }

    static func applyLeadingFadeMask(
        context: inout GraphicsContext,
        rect: CGRect,
        fadeWidth: CGFloat = 20.0
    ) {
        guard rect.width > 1.0 else { return }
        let clampedFade = min(fadeWidth, rect.width)
        let fadeFraction = Double(clampedFade / rect.width)
        context.blendMode = .destinationIn
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: fadeFraction),
                    .init(color: .black, location: 1.0)
                ]),
                startPoint: CGPoint(x: rect.minX, y: 0),
                endPoint: CGPoint(x: rect.maxX, y: 0)
            )
        )
    }

    private static func sliceWithBoundaryAnchors<T>(
        _ items: [T],
        start: TimeInterval,
        end: TimeInterval,
        timestamp: (T) -> TimeInterval
    ) -> [T] {
        guard !items.isEmpty else { return [] }
        var startIdx = items.firstIndex(where: { timestamp($0) >= start }) ?? items.count
        if startIdx > 0 {
            startIdx -= 1
        }
        // Keep up to the newest in-transit sample after `end` so the spline tangent at `edge` is exact.
        var endIdx = items.lastIndex(where: { timestamp($0) <= end }) ?? 0
        if endIdx + 1 < items.count {
            endIdx += 1
        }
        guard startIdx <= endIdx, startIdx < items.count else {
            return Array(items.suffix(2))
        }
        return Array(items[startIdx...endIdx])
    }
}

// MARK: - ChartScrubState & Environment Routing (Task 8.5.4)

/// Scrubbed sample readout routed from `LiveChart` into `PanelScaffold`'s Stocks-style Glance header.
public struct ChartScrubState: Equatable, Sendable {
    public struct SecondaryReadout: Equatable, Sendable {
        public let text: String
        public let unit: String
        public let color: Color
        public let label: String?

        public init(text: String, unit: String, color: Color, label: String? = nil) {
            self.text = text
            self.unit = unit
            self.color = color
            self.label = label
        }
    }

    public let formattedPrimary: String
    public let primaryUnit: String
    public let primaryLabel: String?
    public let secondaryReadout: SecondaryReadout?
    public let relativeTimeText: String
    public let clockTimeText: String
    public let timestamp: TimeInterval?

    public init(
        formattedPrimary: String,
        primaryUnit: String = "",
        primaryLabel: String? = nil,
        secondaryReadout: SecondaryReadout? = nil,
        relativeTimeText: String,
        clockTimeText: String,
        timestamp: TimeInterval? = nil
    ) {
        self.formattedPrimary = formattedPrimary
        self.primaryUnit = primaryUnit
        self.primaryLabel = primaryLabel
        self.secondaryReadout = secondaryReadout
        self.relativeTimeText = relativeTimeText
        self.clockTimeText = clockTimeText
        self.timestamp = timestamp
    }

    /// Combined Glance headline string `"<relativeTimeText> · <clockTimeText>"`.
    public var headlineText: String {
        if clockTimeText.isEmpty {
            return relativeTimeText
        }
        return "\(relativeTimeText) · \(clockTimeText)"
    }

    @MainActor
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Formats elapsed seconds relative to the latest sample (`"now"`, `"12s ago"`, `"2m 15s ago"`).
    public static func formatRelativeTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "now" }
        let sec = Int(seconds.rounded())
        if sec <= 0 {
            return "now"
        } else if sec < 60 {
            return "\(sec)s ago"
        } else if sec < 3600 {
            let m = sec / 60
            let s = sec % 60
            return s == 0 ? "\(m)m ago" : "\(m)m \(s)s ago"
        } else {
            let h = sec / 3600
            let m = (sec % 3600) / 60
            return m == 0 ? "\(h)h ago" : "\(h)h \(m)m ago"
        }
    }

    /// Formats a Unix timestamp as `"HH:mm:ss"`.
    @MainActor
    public static func formatClockTime(timestamp: TimeInterval, timeZone: TimeZone = .current) -> String {
        guard timestamp.isFinite else { return "" }
        clockFormatter.timeZone = timeZone
        return clockFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    /// Splits a formatted metric string (e.g. `"42.3%"`, `"4.60 MiB/s"`, `"1,800 RPM"`) into numeric and unit components.
    public static func splitFormattedValue(_ raw: String) -> (value: String, unit: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        var idx = trimmed.startIndex
        var sawDigit = false
        if trimmed[idx] == "-" || trimmed[idx] == "+" {
            let next = trimmed.index(after: idx)
            if next < trimmed.endIndex && trimmed[next].isASCII && trimmed[next].isNumber {
                idx = next
            }
        }

        while idx < trimmed.endIndex {
            let ch = trimmed[idx]
            if ch.isASCII && ch.isNumber {
                sawDigit = true
                idx = trimmed.index(after: idx)
            } else if (ch == "." || ch == ",") && sawDigit {
                let next = trimmed.index(after: idx)
                if next < trimmed.endIndex && trimmed[next].isASCII && trimmed[next].isNumber {
                    idx = next
                } else {
                    break
                }
            } else {
                break
            }
        }

        guard sawDigit else {
            return (trimmed, "")
        }

        let numPart = String(trimmed[..<idx])
        let unitPart = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
        return (numPart, unitPart)
    }

    /// Builds a `ChartScrubState` from numeric sample values, timestamp, and an optional formatter.
    @MainActor
    public static func make(
        primaryValue: Double,
        secondaryValue: Double? = nil,
        primaryLabel: String? = nil,
        secondaryLabel: String? = nil,
        secondaryColor: Color? = nil,
        timestamp: TimeInterval,
        latestTimestamp: TimeInterval,
        valueFormatter: ((Double) -> String)? = nil,
        timeZone: TimeZone = .current
    ) -> ChartScrubState {
        let primaryRaw = valueFormatter?(primaryValue) ?? String(format: "%.1f", primaryValue)
        let (primaryText, primaryUnit) = splitFormattedValue(primaryRaw)

        let secondary: SecondaryReadout?
        if let secVal = secondaryValue, let secColor = secondaryColor {
            let secRaw = valueFormatter?(secVal) ?? String(format: "%.1f", secVal)
            let (secText, secUnit) = splitFormattedValue(secRaw)
            secondary = SecondaryReadout(text: secText, unit: secUnit, color: secColor, label: secondaryLabel)
        } else {
            secondary = nil
        }

        let secondsAgo = max(0.0, latestTimestamp - timestamp)
        return ChartScrubState(
            formattedPrimary: primaryText,
            primaryUnit: primaryUnit,
            primaryLabel: primaryLabel,
            secondaryReadout: secondary,
            relativeTimeText: formatRelativeTime(secondsAgo),
            clockTimeText: formatClockTime(timestamp: timestamp, timeZone: timeZone),
            timestamp: timestamp
        )
    }
}

/// Environment callback allowing any `LiveChart` inside a `PanelScaffold` (hero or `HistoryPage`)
/// to route `ChartScrubState` updates to the Glance header without coupling to chrome views.
public struct ChartScrubAction: Sendable {
    private let handler: @MainActor @Sendable (ChartScrubState?, UUID?) -> Void

    public init(_ handler: @escaping @MainActor @Sendable (ChartScrubState?) -> Void) {
        self.handler = { state, _ in handler(state) }
    }

    internal init(scopedHandler: @escaping @MainActor @Sendable (ChartScrubState?, UUID?) -> Void) {
        self.handler = scopedHandler
    }

    @MainActor
    public func callAsFunction(_ state: ChartScrubState?) {
        handler(state, nil)
    }

    @MainActor
    internal func callAsFunction(_ state: ChartScrubState?, sourceID: UUID?) {
        handler(state, sourceID)
    }
}

private struct ChartScrubActionKey: EnvironmentKey {
    static let defaultValue: ChartScrubAction? = nil
}

extension EnvironmentValues {
    public var chartScrubAction: ChartScrubAction? {
        get { self[ChartScrubActionKey.self] }
        set { self[ChartScrubActionKey.self] = newValue }
    }
}

// MARK: - ScrubController (Time-Domain Hover & Crosshair Resolution)

/// Resolves continuous pointer coordinates in time domain into sample indices, X/Y screen coordinates,
/// and scrubbed values while coordinating clipboard and peak haptic feedback.
@MainActor
final class ScrubController: ObservableObject {
    @Published private(set) var hoveredIndex: Int?
    @Published private(set) var hoverLocation: CGPoint?
    private var lastHapticPeakFiredIndex: Int?
    private var lastDispatchedState: ChartScrubState?

    struct ResolvedTarget {
        let index: Int
        let x: CGFloat
        let primaryValue: Double
        let secondaryValue: Double?
        let secondsAgo: Double
        let timestamp: TimeInterval
    }

    func resolveTarget(
        atX x: CGFloat,
        plotWidth: CGFloat,
        points: [ChartPoint],
        secondaryPoints: [ChartPoint],
        timeline: ChartTimeline,
        windowDuration: TimeInterval,
        isTimestamped: Bool
    ) -> ResolvedTarget? {
        guard !points.isEmpty, plotWidth > 0 else { return nil }
        let clampedX = min(plotWidth, max(0.0, x))

        if isTimestamped, let latest = points.last?.timestamp {
            let targetTimestamp = timeline.edge - windowDuration * (1.0 - Double(clampedX / plotWidth))
            var bestIdx = 0
            var bestDist = abs(points[0].timestamp - targetTimestamp)
            for i in 1..<points.count {
                let d = abs(points[i].timestamp - targetTimestamp)
                if d < bestDist {
                    bestDist = d
                    bestIdx = i
                }
            }
            let pt = points[bestIdx]
            let snappedX = CGFloat(ChartTimeline.xPosition(
                for: pt.timestamp,
                edge: timeline.edge,
                width: Double(plotWidth),
                window: windowDuration
            ))
            let secVal = (bestIdx < secondaryPoints.count) ? secondaryPoints[bestIdx].value : nil
            let secondsAgo = max(0.0, latest - pt.timestamp)
            return ResolvedTarget(
                index: bestIdx,
                x: min(plotWidth, max(0.0, snappedX)),
                primaryValue: pt.value,
                secondaryValue: secVal,
                secondsAgo: secondsAgo,
                timestamp: pt.timestamp
            )
        } else {
            guard let idx = LiveChartMath.hoverIndex(for: Double(clampedX), totalWidth: Double(plotWidth), count: points.count),
                  idx < points.count else {
                return nil
            }
            let pt = points[idx]
            let snappedX = CGFloat(ChartTimeline.xPosition(
                for: pt.timestamp,
                edge: timeline.edge,
                width: Double(plotWidth),
                window: windowDuration
            ))
            let fallbackX = plotWidth * CGFloat(idx) / CGFloat(max(1, points.count - 1))
            let resolvedX = (snappedX >= 0 && snappedX <= plotWidth) ? snappedX : fallbackX
            let secVal = (idx < secondaryPoints.count) ? secondaryPoints[idx].value : nil
            let latest = points.last?.timestamp ?? pt.timestamp
            let secondsAgo = max(0.0, latest - pt.timestamp)
            return ResolvedTarget(
                index: idx,
                x: resolvedX,
                primaryValue: pt.value,
                secondaryValue: secVal,
                secondsAgo: secondsAgo,
                timestamp: pt.timestamp
            )
        }
    }

    func resolveX(
        forIndex index: Int,
        plotWidth: CGFloat,
        points: [ChartPoint],
        timeline: ChartTimeline,
        windowDuration: TimeInterval
    ) -> CGFloat? {
        guard index >= 0, index < points.count, plotWidth > 0 else { return nil }
        let ts = points[index].timestamp
        let x = CGFloat(ChartTimeline.xPosition(
            for: ts,
            edge: timeline.edge,
            width: Double(plotWidth),
            window: windowDuration
        ))
        return min(plotWidth, max(0.0, x))
    }

    func handleHover(
        phase: HoverPhase,
        plotWidth: CGFloat,
        points: [ChartPoint],
        secondaryPoints: [ChartPoint],
        timeline: ChartTimeline,
        windowDuration: TimeInterval,
        isTimestamped: Bool,
        readoutValueForIndex: ((Int) -> Double)? = nil,
        valueFormatter: ((Double) -> String)?,
        onScrub: ((_ index: Int?, _ value: Double?, _ secondsAgo: Double?) -> Void)?,
        onScrubState: ((ResolvedTarget?) -> Void)? = nil
    ) {
        switch phase {
        case .active(let loc):
            hoverLocation = loc
            guard let target = resolveTarget(
                atX: loc.x,
                plotWidth: plotWidth,
                points: points,
                secondaryPoints: secondaryPoints,
                timeline: timeline,
                windowDuration: windowDuration,
                isTimestamped: isTimestamped
            ) else {
                return
            }
            hoveredIndex = target.index
            let readoutValue = readoutValueForIndex?(target.index) ?? target.primaryValue
            onScrub?(target.index, readoutValue, target.secondsAgo)
            onScrubState?(target)

            let formatted = valueFormatter?(readoutValue) ?? String(format: "%.1f", readoutValue)
            CopyHoverCoordinator.shared.setHoveredText(formatted)

            let values = points.map(\.value)
            let peak = LiveChartMath.peakIndex(values: values)
            if target.index == peak && lastHapticPeakFiredIndex != target.index {
                lastHapticPeakFiredIndex = target.index
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if target.index != peak {
                lastHapticPeakFiredIndex = nil
            }

        case .ended:
            clearHover()
            onScrub?(nil, nil, nil)
            onScrubState?(nil)
        }
    }

    func clearHover() {
        hoverLocation = nil
        hoveredIndex = nil
        lastHapticPeakFiredIndex = nil
        CopyHoverCoordinator.shared.setHoveredText(nil)
    }

    func shouldDispatch(_ state: ChartScrubState?) -> Bool {
        if lastDispatchedState == state {
            return false
        }
        lastDispatchedState = state
        return true
    }
}

// MARK: - LiveChart View

/// Full-bleed, time-domain gliding, interactive hero chart for Instrument panels (ADR 0010 / Task 8.5.3).
public struct LiveChart: View {
    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.chartScrubAction) private var chartScrubAction
    @ObservedObject private var panelController = PanelController.shared

    public let mode: LiveChartMode
    public var category: MetricCategory
    public var height: CGFloat
    public var sampleIntervalSeconds: Double
    public var windowDuration: TimeInterval?
    public var showAverageLine: Bool
    public var showPeakMarker: Bool
    public var showAxisTicks: Bool
    public var showLiveHead: Bool
    public var valueFormatter: ((Double) -> String)?
    public var isolatedChannel: Int?
    public var scrubIndex: Int?
    public var onScrub: ((_ index: Int?, _ value: Double?, _ secondsAgo: Double?) -> Void)?
    public var onScrubStateChange: ((ChartScrubState?) -> Void)?

    @StateObject private var model = ChartModel()
    @StateObject private var scrubController = ScrubController()
    @State private var isWindowKey: Bool = true
    @State private var chartID = UUID()

    private static let crosshairSpring = Animation.spring(response: 0.12, dampingFraction: 0.9)

    private struct ActiveScrubSeries {
        let primary: [ChartPoint]
        let secondary: [ChartPoint]
        let total: [ChartPoint]
        let windowDuration: TimeInterval
    }

    public init(
        category: MetricCategory,
        mode: LiveChartMode,
        height: CGFloat = 84,
        sampleIntervalSeconds: Double = 1.0,
        windowDuration: TimeInterval? = nil,
        showAverageLine: Bool = false,
        showPeakMarker: Bool = false,
        showAxisTicks: Bool = false,
        showLiveHead: Bool = true,
        valueFormatter: ((Double) -> String)? = nil,
        isolatedChannel: Int? = nil,
        scrubIndex: Int? = nil,
        onScrub: ((_ index: Int?, _ value: Double?, _ secondsAgo: Double?) -> Void)? = nil,
        onScrubStateChange: ((ChartScrubState?) -> Void)? = nil
    ) {
        self.category = category
        self.mode = mode
        self.height = height
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.windowDuration = windowDuration
        self.showAverageLine = showAverageLine
        self.showPeakMarker = showPeakMarker
        self.showAxisTicks = showAxisTicks
        self.showLiveHead = showLiveHead
        self.valueFormatter = valueFormatter
        self.isolatedChannel = isolatedChannel
        self.scrubIndex = scrubIndex
        self.onScrub = onScrub
        self.onScrubStateChange = onScrubStateChange
    }

    /// Returns the `TimelineView` update interval: `1/60 s` when key/transient, `1/30 s` when pinned & non-key.
    public static func frameInterval(isPinnedNonKey: Bool) -> TimeInterval {
        isPinnedNonKey ? (1.0 / 30.0) : (1.0 / 60.0)
    }

    private var isPinnedNonKey: Bool {
        guard let pinnedPanel = panelController.pinnedPanels[category], pinnedPanel.isVisible else {
            return false
        }
        return !(pinnedPanel.isKeyWindow && isWindowKey)
    }

    public var resolvedPrimaryValues: [Double] {
        if let iso = isolatedChannel {
            switch mode.payload {
            case .stacked(let pts, _, _, _, _, _):
                return pts.map { iso == 1 ? $0.secondary : $0.primary }
            case .mirrored(let pts, _, _, _, _, _, _, _):
                return pts.map { iso == 1 ? $0.secondary : $0.primary }
            case .mirroredEnvelope(let top, let bot, _, _, _, _, _, _):
                return (iso == 1 ? bot : top).map(\.mean)
            default:
                return mode.primaryValues
            }
        }
        if case .stacked(let pts, _, _, _, _, _) = mode.payload {
            return pts.map { $0.primary + $0.secondary }
        }
        return mode.primaryValues
    }

    public var resolvedPrimaryColor: Color {
        if let iso = isolatedChannel {
            switch mode.payload {
            case .stacked(_, let p, let s, _, _, _):
                return iso == 1 ? s : p
            case .mirrored(_, let top, let bot, _, _, _, _, _):
                return iso == 1 ? bot : top
            case .mirroredEnvelope(_, _, let top, let bot, _, _, _, _):
                return iso == 1 ? bot : top
            default:
                return mode.primaryColor
            }
        }
        return mode.primaryColor
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let chartHeight = proxy.size.height
            let activeIndex = scrubController.hoveredIndex ?? scrubIndex
            let isScrubbing = (activeIndex != nil)
            let headInset: CGFloat = showLiveHead ? 5.0 : 0.0
            let plotWidth = max(1.0, width - headInset)
            let minimumInterval = Self.frameInterval(isPinnedNonKey: isPinnedNonKey)

            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: minimumInterval, paused: motionPolicy != .full || isScrubbing)) { timeline in
                    let now = timeline.date.timeIntervalSince1970
                    let resolved = model.step(
                        now: now,
                        mode: mode,
                        category: category,
                        sampleInterval: sampleIntervalSeconds,
                        explicitWindow: windowDuration,
                        isScrubbing: isScrubbing,
                        motionPolicy: motionPolicy
                    )
                    canvasContent(
                        resolved: resolved,
                        width: width,
                        plotWidth: plotWidth,
                        height: chartHeight
                    )
                }

                // Interactive Crosshair v2 (hairline + curve-snapped beads; no floating pill)
                if let index = activeIndex {
                    let activeSeries = activeScrubPoints(now: Date().timeIntervalSince1970)
                    let refPoints = referencePoints(for: activeSeries)
                    if index >= 0, index < refPoints.count,
                       let x = scrubController.resolveX(
                           forIndex: index,
                           plotWidth: plotWidth,
                           points: refPoints,
                           timeline: model.timeline,
                           windowDuration: activeSeries.windowDuration
                       ) {
                        crosshairOverlay(
                            x: x,
                            index: index,
                            activeSeries: activeSeries,
                            height: chartHeight
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                let activeSeries = activeScrubPoints(now: Date().timeIntervalSince1970)
                let refPoints = referencePoints(for: activeSeries)
                scrubController.handleHover(
                    phase: phase,
                    plotWidth: plotWidth,
                    points: refPoints,
                    secondaryPoints: activeSeries.secondary,
                    timeline: model.timeline,
                    windowDuration: activeSeries.windowDuration,
                    isTimestamped: mode.isTimestamped,
                    readoutValueForIndex: { idx in
                        primaryNumericValue(atIndex: idx, activeSeries: activeSeries) ?? 0.0
                    },
                    valueFormatter: valueFormatter,
                    onScrub: onScrub,
                    onScrubState: { target in
                        if let target {
                            let state = buildScrubState(atIndex: target.index, activeSeries: activeSeries)
                            dispatchScrubState(state)
                        } else if let idx = scrubIndex {
                            let state = buildScrubState(atIndex: idx, activeSeries: activeSeries)
                            dispatchScrubState(state)
                        } else {
                            dispatchScrubState(nil)
                        }
                    }
                )
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
        .onAppear {
            refreshWindowKeyState()
            if let idx = scrubIndex, scrubController.hoveredIndex == nil {
                let activeSeries = activeScrubPoints(now: Date().timeIntervalSince1970)
                dispatchScrubState(buildScrubState(atIndex: idx, activeSeries: activeSeries))
            }
        }
        .onChange(of: scrubIndex) { newIndex in
            guard scrubController.hoveredIndex == nil else { return }
            if let idx = newIndex {
                let activeSeries = activeScrubPoints(now: Date().timeIntervalSince1970)
                dispatchScrubState(buildScrubState(atIndex: idx, activeSeries: activeSeries))
            } else {
                dispatchScrubState(nil)
            }
        }
        .onDisappear {
            if scrubController.hoveredIndex != nil || scrubIndex != nil {
                scrubController.clearHover()
                dispatchScrubState(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshWindowKeyState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            refreshWindowKeyState()
        }
    }

    private func refreshWindowKeyState() {
        if let pinned = panelController.pinnedPanels[category], pinned.isVisible {
            isWindowKey = pinned.isKeyWindow
        } else {
            isWindowKey = true
        }
    }

    private func activeScrubPoints(now: TimeInterval) -> ActiveScrubSeries {
        let resolved = model.resolveSeries(
            mode: mode,
            now: now,
            sampleInterval: max(1e-3, sampleIntervalSeconds),
            explicitWindow: windowDuration
        )
        return ActiveScrubSeries(
            primary: resolved.primaryPoints,
            secondary: resolved.secondaryPoints,
            total: resolved.totalPoints,
            windowDuration: resolved.windowDuration
        )
    }

    private func referencePoints(for series: ActiveScrubSeries) -> [ChartPoint] {
        switch mode.payload {
        case .stacked:
            if isolatedChannel == 0 { return series.primary }
            if isolatedChannel == 1 { return series.secondary }
            return series.total
        case .mirrored, .mirroredEnvelope:
            if isolatedChannel == 1 && !series.secondary.isEmpty {
                return series.secondary
            }
            return series.primary
        default:
            return series.primary
        }
    }

    private func primaryNumericValue(atIndex index: Int, activeSeries: ActiveScrubSeries) -> Double? {
        switch mode.payload {
        case .stacked:
            if isolatedChannel == 0 {
                return index < activeSeries.primary.count ? activeSeries.primary[index].value : nil
            } else if isolatedChannel == 1 {
                return index < activeSeries.secondary.count ? activeSeries.secondary[index].value : nil
            }
            return index < activeSeries.total.count ? activeSeries.total[index].value : nil
        case .mirrored, .mirroredEnvelope:
            if isolatedChannel == 1 {
                return index < activeSeries.secondary.count ? activeSeries.secondary[index].value : nil
            }
            return index < activeSeries.primary.count ? activeSeries.primary[index].value : nil
        default:
            return index < activeSeries.primary.count ? activeSeries.primary[index].value : nil
        }
    }

    private func dispatchScrubState(_ state: ChartScrubState?) {
        guard scrubController.shouldDispatch(state) else { return }
        onScrubStateChange?(state)
        chartScrubAction?(state, sourceID: chartID)
    }

    private func buildScrubState(atIndex index: Int, activeSeries: ActiveScrubSeries) -> ChartScrubState? {
        let refPts = referencePoints(for: activeSeries)
        guard index >= 0, index < refPts.count,
              let primaryVal = primaryNumericValue(atIndex: index, activeSeries: activeSeries) else {
            return nil
        }

        let timestamp = refPts[index].timestamp
        let latestTimestamp = refPts.last?.timestamp ?? timestamp

        switch mode.payload {
        case .mirrored(_, _, let botColor, let topLbl, let botLbl, _, _, _),
             .mirroredEnvelope(_, _, _, let botColor, let topLbl, let botLbl, _, _):
            if isolatedChannel == 0 {
                return ChartScrubState.make(
                    primaryValue: primaryVal,
                    primaryLabel: topLbl,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: valueFormatter
                )
            } else if isolatedChannel == 1 {
                return ChartScrubState.make(
                    primaryValue: primaryVal,
                    primaryLabel: botLbl,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: valueFormatter
                )
            } else {
                let secVal = index < activeSeries.secondary.count ? activeSeries.secondary[index].value : nil
                return ChartScrubState.make(
                    primaryValue: primaryVal,
                    secondaryValue: secVal,
                    primaryLabel: topLbl,
                    secondaryLabel: botLbl,
                    secondaryColor: botColor,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: valueFormatter
                )
            }
        default:
            return ChartScrubState.make(
                primaryValue: primaryVal,
                timestamp: timestamp,
                latestTimestamp: latestTimestamp,
                valueFormatter: valueFormatter
            )
        }
    }

    // MARK: - Canvas Rendering

    @ViewBuilder
    private func canvasContent(
        resolved: ChartModel.ResolvedSeries,
        width: CGFloat,
        plotWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let pW = max(1.0, min(w, plotWidth))
            let plotRect = CGRect(x: 0, y: 0, width: pW, height: h)

            switch mode.payload {
            case .single(_, let color, let deepColor, _, _, _):
                drawSingleAxisCanvas(
                    context: &context,
                    resolved: resolved,
                    width: w,
                    plotWidth: pW,
                    height: h,
                    color: color,
                    deepColor: deepColor,
                    bands: [],
                    buckets: nil
                )

            case .banded(_, let bands, _, _, _):
                let baseColor = CategoryPalette.tint(for: category)
                drawSingleAxisCanvas(
                    context: &context,
                    resolved: resolved,
                    width: w,
                    plotWidth: pW,
                    height: h,
                    color: baseColor,
                    deepColor: baseColor,
                    bands: bands,
                    buckets: nil
                )

            case .envelope(let buckets, let color, let deepColor, let bands, _, _):
                drawSingleAxisCanvas(
                    context: &context,
                    resolved: resolved,
                    width: w,
                    plotWidth: pW,
                    height: h,
                    color: color,
                    deepColor: deepColor,
                    bands: bands,
                    buckets: buckets
                )

            case .stacked(_, let primaryColor, let secondaryColor, _, _, _):
                let range = ChartRenderer.VerticalRange(
                    floor: model.topScale.displayedFloor,
                    ceiling: model.topScale.displayedCeiling,
                    topY: 0.0,
                    baselineY: h,
                    inverted: false
                )
                if showAxisTicks {
                    ChartRenderer.drawStandardGrid(context: &context, scale: model.topScale, verticalRange: range, width: w, valueFormatter: valueFormatter)
                }
                let primaryOpacity = (isolatedChannel == 1 ? 0.15 : 1.0)
                let secondaryOpacity = (isolatedChannel == 0 ? 0.15 : 1.0)
                let primaryGeom = ChartRenderer.buildSeriesGeometry(
                    points: resolved.primaryPoints,
                    timeline: model.timeline,
                    windowDuration: resolved.windowDuration,
                    plotWidth: pW,
                    verticalRange: range
                )
                let totalGeom = ChartRenderer.buildSeriesGeometry(
                    points: resolved.totalPoints,
                    timeline: model.timeline,
                    windowDuration: resolved.windowDuration,
                    plotWidth: pW,
                    verticalRange: range
                )
                context.drawLayer { layerCtx in
                    layerCtx.clip(to: Path(plotRect))
                    if let totalGeom {
                        ChartRenderer.drawSeries(
                            context: &layerCtx,
                            geometry: totalGeom,
                            verticalRange: range,
                            plotWidth: pW,
                            style: ChartRenderer.RenderStyle(
                                color: secondaryColor,
                                deepColor: secondaryColor,
                                opacity: secondaryOpacity,
                                isDashed: differentiateWithoutColor,
                                bands: [],
                                drawAreaFill: true,
                                colorScheme: colorScheme,
                                colorSchemeContrast: colorSchemeContrast
                            )
                        )
                    }
                    if let primaryGeom {
                        ChartRenderer.drawSeries(
                            context: &layerCtx,
                            geometry: primaryGeom,
                            verticalRange: range,
                            plotWidth: pW,
                            style: ChartRenderer.RenderStyle(
                                color: primaryColor,
                                deepColor: primaryColor,
                                opacity: primaryOpacity,
                                isDashed: false,
                                bands: [],
                                drawAreaFill: true,
                                colorScheme: colorScheme,
                                colorSchemeContrast: colorSchemeContrast
                            )
                        )
                    }
                    ChartRenderer.applyLeadingFadeMask(context: &layerCtx, rect: plotRect)
                }

                let activePoints = (isolatedChannel == 0)
                    ? resolved.primaryPoints
                    : (isolatedChannel == 1 ? resolved.secondaryPoints : resolved.totalPoints)
                let peakPoints = (isolatedChannel == 0) ? resolved.primaryPoints : resolved.totalPoints
                let headGeom = (isolatedChannel == 0) ? primaryGeom : totalGeom
                drawCanvasOverlays(
                    context: &context,
                    averagePoints: activePoints,
                    peakPoints: peakPoints,
                    range: range,
                    plotWidth: pW,
                    totalWidth: w,
                    windowDuration: resolved.windowDuration,
                    overlayColor: resolvedPrimaryColor,
                    headPoint: headGeom?.headPoint,
                    headColor: primaryColor,
                    headOpacity: 1.0
                )

            case .mirrored(_, let topColor, let bottomColor, let topLabel, let bottomLabel, _, _, _):
                drawMirroredCanvas(
                    context: &context,
                    resolved: resolved,
                    width: w,
                    plotWidth: pW,
                    height: h,
                    topColor: topColor,
                    bottomColor: bottomColor,
                    topLabel: topLabel,
                    bottomLabel: bottomLabel,
                    topBuckets: nil,
                    bottomBuckets: nil
                )

            case .mirroredEnvelope(let topBuckets, let botBuckets, let topColor, let bottomColor, let topLabel, let bottomLabel, _, _):
                drawMirroredCanvas(
                    context: &context,
                    resolved: resolved,
                    width: w,
                    plotWidth: pW,
                    height: h,
                    topColor: topColor,
                    bottomColor: bottomColor,
                    topLabel: topLabel,
                    bottomLabel: bottomLabel,
                    topBuckets: topBuckets,
                    bottomBuckets: botBuckets
                )
            }
        }
    }

    private func drawSingleAxisCanvas(
        context: inout GraphicsContext,
        resolved: ChartModel.ResolvedSeries,
        width: CGFloat,
        plotWidth: CGFloat,
        height: CGFloat,
        color: Color,
        deepColor: Color,
        bands: [ChartBand],
        buckets: [BucketPoint]?
    ) {
        let plotRect = CGRect(x: 0, y: 0, width: plotWidth, height: height)
        let range = ChartRenderer.VerticalRange(
            floor: model.topScale.displayedFloor,
            ceiling: model.topScale.displayedCeiling,
            topY: 0.0,
            baselineY: height,
            inverted: false
        )
        if showAxisTicks {
            ChartRenderer.drawStandardGrid(context: &context, scale: model.topScale, verticalRange: range, width: width, valueFormatter: valueFormatter)
        }

        let envelopePath = buckets.flatMap {
            ChartRenderer.buildEnvelopePolygon(
                buckets: $0,
                timeline: model.timeline,
                windowDuration: resolved.windowDuration,
                plotWidth: plotWidth,
                verticalRange: range
            )
        }
        guard let geometry = ChartRenderer.buildSeriesGeometry(
            points: resolved.primaryPoints,
            timeline: model.timeline,
            windowDuration: resolved.windowDuration,
            plotWidth: plotWidth,
            verticalRange: range
        ) else { return }

        let currentVal = resolved.primaryPoints.last?.value ?? 0.0
        let activeColor = bands.isEmpty
            ? color
            : (bands.sorted { $0.threshold < $1.threshold }.last(where: { currentVal >= $0.threshold })?.color ?? color)

        context.drawLayer { layerCtx in
            layerCtx.clip(to: Path(plotRect))
            if let envelopePath {
                layerCtx.fill(envelopePath, with: .color(color.opacity(0.14)))
            }
            ChartRenderer.drawSeries(
                context: &layerCtx,
                geometry: geometry,
                verticalRange: range,
                plotWidth: plotWidth,
                style: ChartRenderer.RenderStyle(
                    color: color,
                    deepColor: deepColor,
                    opacity: 1.0,
                    isDashed: false,
                    bands: bands,
                    drawAreaFill: envelopePath == nil,
                    colorScheme: colorScheme,
                    colorSchemeContrast: colorSchemeContrast
                )
            )
            ChartRenderer.applyLeadingFadeMask(context: &layerCtx, rect: plotRect)
        }

        drawCanvasOverlays(
            context: &context,
            averagePoints: resolved.primaryPoints,
            peakPoints: resolved.primaryPoints,
            range: range,
            plotWidth: plotWidth,
            totalWidth: width,
            windowDuration: resolved.windowDuration,
            overlayColor: activeColor,
            headPoint: geometry.headPoint,
            headColor: activeColor,
            headOpacity: 1.0
        )
    }

    private func drawMirroredCanvas(
        context: inout GraphicsContext,
        resolved: ChartModel.ResolvedSeries,
        width: CGFloat,
        plotWidth: CGFloat,
        height: CGFloat,
        topColor: Color,
        bottomColor: Color,
        topLabel: String,
        bottomLabel: String,
        topBuckets: [BucketPoint]?,
        bottomBuckets: [BucketPoint]?
    ) {
        let plotRect = CGRect(x: 0, y: 0, width: plotWidth, height: height)
        let midY = height / 2.0
        let topRange = ChartRenderer.VerticalRange(
            floor: model.topScale.displayedFloor,
            ceiling: model.topScale.displayedCeiling,
            topY: 0.0,
            baselineY: midY,
            inverted: false
        )
        let botRange = ChartRenderer.VerticalRange(
            floor: model.bottomScale.displayedFloor,
            ceiling: model.bottomScale.displayedCeiling,
            topY: height,
            baselineY: midY,
            inverted: true
        )
        ChartRenderer.drawMirroredGridAndLabels(
            context: &context,
            topScale: model.topScale,
            bottomScale: model.bottomScale,
            topLabel: topLabel,
            bottomLabel: bottomLabel,
            width: width,
            height: height,
            showHairlines: showAxisTicks,
            valueFormatter: valueFormatter
        )

        let topOpacity = (isolatedChannel == 1 ? 0.15 : 1.0)
        let botOpacity = (isolatedChannel == 0 ? 0.15 : 1.0)
        let topEnvelope = topBuckets.flatMap {
            ChartRenderer.buildEnvelopePolygon(
                buckets: $0,
                timeline: model.timeline,
                windowDuration: resolved.windowDuration,
                plotWidth: plotWidth,
                verticalRange: topRange
            )
        }
        let botEnvelope = bottomBuckets.flatMap {
            ChartRenderer.buildEnvelopePolygon(
                buckets: $0,
                timeline: model.timeline,
                windowDuration: resolved.windowDuration,
                plotWidth: plotWidth,
                verticalRange: botRange
            )
        }
        let topGeom = ChartRenderer.buildSeriesGeometry(
            points: resolved.primaryPoints,
            timeline: model.timeline,
            windowDuration: resolved.windowDuration,
            plotWidth: plotWidth,
            verticalRange: topRange
        )
        let botGeom = ChartRenderer.buildSeriesGeometry(
            points: resolved.secondaryPoints,
            timeline: model.timeline,
            windowDuration: resolved.windowDuration,
            plotWidth: plotWidth,
            verticalRange: botRange
        )

        context.drawLayer { layerCtx in
            layerCtx.clip(to: Path(plotRect))
            if let topEnvelope {
                layerCtx.fill(topEnvelope, with: .color(topColor.opacity(0.14 * topOpacity)))
            }
            if let botEnvelope {
                layerCtx.fill(botEnvelope, with: .color(bottomColor.opacity(0.14 * botOpacity)))
            }
            if let topGeom {
                ChartRenderer.drawSeries(
                    context: &layerCtx,
                    geometry: topGeom,
                    verticalRange: topRange,
                    plotWidth: plotWidth,
                    style: ChartRenderer.RenderStyle(
                        color: topColor,
                        deepColor: topColor,
                        opacity: topOpacity,
                        isDashed: false,
                        bands: [],
                        drawAreaFill: topEnvelope == nil,
                        colorScheme: colorScheme,
                        colorSchemeContrast: colorSchemeContrast
                    )
                )
            }
            if let botGeom {
                ChartRenderer.drawSeries(
                    context: &layerCtx,
                    geometry: botGeom,
                    verticalRange: botRange,
                    plotWidth: plotWidth,
                    style: ChartRenderer.RenderStyle(
                        color: bottomColor,
                        deepColor: bottomColor,
                        opacity: botOpacity,
                        isDashed: differentiateWithoutColor,
                        bands: [],
                        drawAreaFill: botEnvelope == nil,
                        colorScheme: colorScheme,
                        colorSchemeContrast: colorSchemeContrast
                    )
                )
            }
            ChartRenderer.applyLeadingFadeMask(context: &layerCtx, rect: plotRect)
        }

        let isBottom = (isolatedChannel == 1)
        let activePoints = isBottom ? resolved.secondaryPoints : resolved.primaryPoints
        let activeRange = isBottom ? botRange : topRange
        drawCanvasOverlays(
            context: &context,
            averagePoints: activePoints,
            peakPoints: activePoints,
            range: activeRange,
            plotWidth: plotWidth,
            totalWidth: width,
            windowDuration: resolved.windowDuration,
            overlayColor: resolvedPrimaryColor,
            headPoint: nil,
            headColor: topColor,
            headOpacity: 1.0
        )
        if showLiveHead {
            if let topHead = topGeom?.headPoint {
                ChartRenderer.drawHeadBead(context: &context, at: topHead, color: topColor, opacity: topOpacity)
            }
            if let botHead = botGeom?.headPoint {
                ChartRenderer.drawHeadBead(context: &context, at: botHead, color: bottomColor, opacity: botOpacity)
            }
        }
    }

    private func drawCanvasOverlays(
        context: inout GraphicsContext,
        averagePoints: [ChartPoint],
        peakPoints: [ChartPoint],
        range: ChartRenderer.VerticalRange,
        plotWidth: CGFloat,
        totalWidth: CGFloat,
        windowDuration: TimeInterval,
        overlayColor: Color,
        headPoint: CGPoint?,
        headColor: Color,
        headOpacity: Double
    ) {
        if showAverageLine {
            ChartRenderer.drawAverageLine(context: &context, points: averagePoints, verticalRange: range, width: totalWidth, color: overlayColor)
        }
        if showPeakMarker {
            ChartRenderer.drawPeakMarker(context: &context, points: peakPoints, timeline: model.timeline, windowDuration: windowDuration, plotWidth: plotWidth, totalWidth: totalWidth, verticalRange: range, color: overlayColor, valueFormatter: valueFormatter)
        }
        if showLiveHead, let headPoint {
            ChartRenderer.drawHeadBead(context: &context, at: headPoint, color: headColor, opacity: headOpacity)
        }
    }

    // MARK: - Interaction & Crosshair v2 (Task 8.5.4)

    @ViewBuilder
    private func crosshairOverlay(
        x: CGFloat,
        index: Int,
        activeSeries: ActiveScrubSeries,
        height: CGFloat
    ) -> some View {
        let primaryPts = activeSeries.primary
        let anim: Animation? = (motionPolicy == .full) ? Self.crosshairSpring : nil

        switch mode.payload {
        case .mirrored(_, let topCol, let botCol, _, _, _, _, _),
             .mirroredEnvelope(_, _, let topCol, let botCol, _, _, _, _):
            let midY = height / 2.0
            let topRange = ChartRenderer.VerticalRange(
                floor: model.topScale.displayedFloor,
                ceiling: model.topScale.displayedCeiling,
                topY: 0.0,
                baselineY: midY,
                inverted: false
            )
            let botRange = ChartRenderer.VerticalRange(
                floor: model.bottomScale.displayedFloor,
                ceiling: model.bottomScale.displayedCeiling,
                topY: height,
                baselineY: midY,
                inverted: true
            )
            let refPts = referencePoints(for: activeSeries)
            let sampleTs = index < refPts.count ? refPts[index].timestamp : (refPts.last?.timestamp ?? 0.0)
            let topVal = index < primaryPts.count
                ? (ChartTimeline.interpolateValue(at: sampleTs, points: primaryPts) ?? primaryPts[index].value)
                : 0.0
            let botPts = activeSeries.secondary
            let botVal = index < botPts.count
                ? (ChartTimeline.interpolateValue(at: sampleTs, points: botPts) ?? botPts[index].value)
                : 0.0

            let topY = topRange.yPosition(for: topVal)
            let botY = botRange.yPosition(for: botVal)

            ZStack(alignment: .topLeading) {
                crosshairHairline(x: x, height: height)

                if isolatedChannel == nil || isolatedChannel == 0 {
                    crosshairBead(at: CGPoint(x: x, y: topY), color: topCol)
                }
                if isolatedChannel == nil || isolatedChannel == 1 {
                    crosshairBead(at: CGPoint(x: x, y: botY), color: botCol)
                }
            }
            .animation(anim, value: x)

        case .stacked(_, let primaryCol, let secondaryCol, _, _, _):
            let range = ChartRenderer.VerticalRange(
                floor: model.topScale.displayedFloor,
                ceiling: model.topScale.displayedCeiling,
                topY: 0.0,
                baselineY: height,
                inverted: false
            )
            let refPts = referencePoints(for: activeSeries)
            let sampleTs = index < refPts.count ? refPts[index].timestamp : (refPts.last?.timestamp ?? 0.0)

            ZStack(alignment: .topLeading) {
                crosshairHairline(x: x, height: height)

                if isolatedChannel != 1, index < activeSeries.primary.count {
                    let primVal = ChartTimeline.interpolateValue(at: sampleTs, points: activeSeries.primary)
                        ?? activeSeries.primary[index].value
                    crosshairBead(at: CGPoint(x: x, y: range.yPosition(for: primVal)), color: primaryCol)
                }
                if isolatedChannel != 0, index < activeSeries.total.count {
                    let totalVal = ChartTimeline.interpolateValue(at: sampleTs, points: activeSeries.total)
                        ?? activeSeries.total[index].value
                    crosshairBead(at: CGPoint(x: x, y: range.yPosition(for: totalVal)), color: secondaryCol)
                }
            }
            .animation(anim, value: x)

        case .banded(_, let bands, _, _, _),
             .envelope(_, _, _, let bands, _, _):
            if index < primaryPts.count {
                let sampleTs = primaryPts[index].timestamp
                let val = ChartTimeline.interpolateValue(at: sampleTs, points: primaryPts) ?? primaryPts[index].value
                let range = ChartRenderer.VerticalRange(
                    floor: model.topScale.displayedFloor,
                    ceiling: model.topScale.displayedCeiling,
                    topY: 0.0,
                    baselineY: height,
                    inverted: false
                )
                let pointY = range.yPosition(for: val)
                let baseColor = resolvedPrimaryColor
                let beadColor = bands.isEmpty
                    ? baseColor
                    : (bands.sorted { $0.threshold < $1.threshold }.last(where: { val >= $0.threshold })?.color ?? baseColor)

                ZStack(alignment: .topLeading) {
                    crosshairHairline(x: x, height: height)
                    crosshairBead(at: CGPoint(x: x, y: pointY), color: beadColor)
                }
                .animation(anim, value: x)
            }

        case .single:
            if index < primaryPts.count {
                let sampleTs = primaryPts[index].timestamp
                let val = ChartTimeline.interpolateValue(at: sampleTs, points: primaryPts) ?? primaryPts[index].value
                let range = ChartRenderer.VerticalRange(
                    floor: model.topScale.displayedFloor,
                    ceiling: model.topScale.displayedCeiling,
                    topY: 0.0,
                    baselineY: height,
                    inverted: false
                )
                let pointY = range.yPosition(for: val)

                ZStack(alignment: .topLeading) {
                    crosshairHairline(x: x, height: height)
                    crosshairBead(at: CGPoint(x: x, y: pointY), color: resolvedPrimaryColor)
                }
                .animation(anim, value: x)
            }
        }
    }

    private func crosshairHairline(x: CGFloat, height: CGFloat) -> some View {
        let fadeFraction = height > 0 ? min(0.5, Double(6.0 / height)) : 0.0
        let lineColor = Color.primary.opacity(0.30)
        return Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: lineColor, location: fadeFraction),
                        .init(color: lineColor, location: 1.0 - fadeFraction),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: height)
            .position(x: x, y: height / 2.0)
    }

    private func crosshairBead(at point: CGPoint, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(Instrument.Surface.panel, lineWidth: 1.5)
            )
            .position(point)
    }

    private func copyScrubbedValue() {
        let activeSeries = activeScrubPoints(now: Date().timeIntervalSince1970)
        let idx = scrubController.hoveredIndex ?? scrubIndex
        guard let validIdx = idx,
              let val = primaryNumericValue(atIndex: validIdx, activeSeries: activeSeries) else { return }
        let formatted = valueFormatter?(val) ?? String(format: "%.1f", val)
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
        let now = Date().timeIntervalSince1970
        let samplePoints = (0..<60).map { i in
            ChartPoint(timestamp: now - Double(59 - i), value: Double.random(in: 10...95))
        }
        let buckets = (0..<40).map { i in
            let mean = 45.0 + sin(Double(i) * 0.25) * 20.0
            return BucketPoint(timestamp: now - Double(39 - i) * 7.5, min: max(0, mean - 12), max: min(100, mean + 15), mean: mean)
        }

        VStack(spacing: 20) {
            LiveChart(
                category: .cpu,
                mode: .single(values: Array(repeating: 25.0, count: 60), color: .blue),
                showAverageLine: true
            )

            LiveChart(
                category: .network,
                mode: .single(points: samplePoints, color: .teal),
                showPeakMarker: true,
                showAxisTicks: true
            )

            LiveChart(
                category: .memory,
                mode: .envelope(buckets: buckets, color: .purple),
                windowDuration: 300.0,
                showAxisTicks: true
            )

            LiveChart(
                category: .cpu,
                mode: .stacked(
                    primary: (0..<40).map { _ in Double.random(in: 10...40) },
                    secondary: (0..<40).map { _ in Double.random(in: 5...30) },
                    primaryColor: .blue,
                    secondaryColor: .cyan
                )
            )

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
