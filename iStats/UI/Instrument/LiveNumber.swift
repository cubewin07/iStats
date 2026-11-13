import SwiftUI
import iStatsCore

/// Cadence gate for `LiveNumber` (Task 8.5.7 / A12).
/// - Integer formatted strings update on every sample (preserving smooth `.numericText` rolling).
/// - Fractional formatted strings (containing `.`) enforce a `2.0 s` minimum cadence gate unless
///   `abs(newValue - displayedValue) >= 1.0`.
public struct LiveNumberCadenceGate: Equatable, Sendable {
    public private(set) var displayedValue: Double
    public private(set) var lastCommittedAt: TimeInterval
    public let minimumInterval: TimeInterval
    public let bypassDelta: Double

    public init(
        initialValue: Double,
        now: TimeInterval = 0,
        minimumInterval: TimeInterval = 2.0,
        bypassDelta: Double = 1.0
    ) {
        self.displayedValue = initialValue
        self.lastCommittedAt = now
        self.minimumInterval = minimumInterval
        self.bypassDelta = bypassDelta
    }

    /// Evaluates whether `newValue` at `now` should update `displayedValue`.
    /// - Returns: `true` if `displayedValue` was updated; `false` if gated.
    @discardableResult
    public mutating func evaluate(
        newValue: Double,
        formatted: String,
        now: TimeInterval
    ) -> Bool {
        if !formatted.contains(".") {
            displayedValue = newValue
            lastCommittedAt = now
            return true
        }

        let delta = abs(newValue - displayedValue)
        let elapsed = now - lastCommittedAt
        if delta >= bypassDelta || elapsed >= minimumInterval {
            displayedValue = newValue
            lastCommittedAt = now
            return true
        }
        return false
    }
}

/// An instrument-grade animated numeral with rolling tabular digits and baseline unit alignment.
public struct LiveNumber: View {
    public let value: Double
    public let format: (Double) -> String
    public let font: Font
    public let unit: String?
    public let unitFont: Font
    public let interval: Double

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var gate: LiveNumberCadenceGate
    @State private var pendingFlushItem: DispatchWorkItem?

    public init(
        value: Double,
        format: @escaping (Double) -> String = { String(format: "%.0f", $0) },
        font: Font = Instrument.Typography.display,
        unit: String? = nil,
        unitFont: Font = Instrument.Typography.unit,
        interval: Double = 1.0
    ) {
        self.value = value
        self.format = format
        self.font = font
        self.unit = unit
        self.unitFont = unitFont
        self.interval = interval
        self._gate = State(initialValue: LiveNumberCadenceGate(
            initialValue: value,
            now: ProcessInfo.processInfo.systemUptime
        ))
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            numberView
            if let unit = unit {
                Text(unit)
                    .font(unitFont)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(accessibilityText)
        .onChange(of: value) { newValue in
            handleValueChange(newValue)
        }
        .onDisappear {
            pendingFlushItem?.cancel()
            pendingFlushItem = nil
        }
    }

    private func handleValueChange(_ newValue: Double) {
        pendingFlushItem?.cancel()
        pendingFlushItem = nil

        let now = ProcessInfo.processInfo.systemUptime
        let formatted = format(newValue)
        if gate.evaluate(newValue: newValue, formatted: formatted, now: now) {
            return
        }

        let delay = max(0.01, gate.minimumInterval - (now - gate.lastCommittedAt))
        let stateGate = _gate
        let work = DispatchWorkItem {
            let flushNow = ProcessInfo.processInfo.systemUptime
            stateGate.wrappedValue.evaluate(
                newValue: newValue,
                formatted: formatted,
                now: flushNow
            )
        }
        pendingFlushItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @ViewBuilder
    private var numberView: some View {
        let shownValue = gate.displayedValue
        let text = format(shownValue)

        if #available(macOS 14.0, *) {
            if motionPolicy == .full {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
                    .contentTransition(.numericText(value: shownValue))
                    .animation(Motion.value(interval: interval), value: shownValue)
            } else if motionPolicy == .reduced {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: text)
            } else {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
            }
        } else {
            if motionPolicy.allowsEasing {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
                    .id(text)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: text)
            } else {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
            }
        }
    }

    private var opticalTracking: CGFloat {
        if font == Instrument.Typography.display {
            return -1.2
        } else if font == Instrument.Typography.displayCompact {
            return -0.6
        } else {
            return 0.0
        }
    }

    private var accessibilityText: String {
        let formatted = format(gate.displayedValue)
        if let u = unit {
            return "\(formatted) \(u)"
        }
        return formatted
    }
}

// MARK: - Eased Progress Modifier

public struct EasedProgressModifier: ViewModifier {
    public let progress: Double
    public let interval: Double
    @Environment(\.motionPolicy) private var motionPolicy

    public func body(content: Content) -> some View {
        if motionPolicy == .full {
            content.animation(Motion.value(interval: interval), value: progress)
        } else if motionPolicy == .reduced {
            content.animation(.easeInOut(duration: 0.15), value: progress)
        } else {
            content.animation(nil, value: progress)
        }
    }
}

extension View {
    /// Eases changes to progress / meter values respecting the active `MotionPolicy`.
    public func easedProgress(_ progress: Double, interval: Double = 1.0) -> some View {
        modifier(EasedProgressModifier(progress: progress, interval: interval))
    }
}

// MARK: - Previews

#Preview("LiveNumber Policies") {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 4) {
            Text("POLICY: FULL").font(Instrument.Typography.eyebrow).foregroundStyle(.secondary)
            LiveNumber(value: 84.0, format: { "\(Int($0))" }, unit: "%")
                .motionPolicy(.full)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("POLICY: REDUCED").font(Instrument.Typography.eyebrow).foregroundStyle(.secondary)
            LiveNumber(value: 84.0, format: { "\(Int($0))" }, unit: "%")
                .motionPolicy(.reduced)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("POLICY: FROZEN").font(Instrument.Typography.eyebrow).foregroundStyle(.secondary)
            LiveNumber(value: 84.0, format: { "\(Int($0))" }, unit: "%")
                .motionPolicy(.frozen)
        }
    }
    .padding()
    .frame(width: 300)
}
