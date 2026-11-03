import SwiftUI
import iStatsCore

/// An instrument-grade animated numeral with rolling tabular digits and baseline unit alignment.
public struct LiveNumber: View {
    public let value: Double
    public let format: (Double) -> String
    public let font: Font
    public let unit: String?
    public let unitFont: Font

    @Environment(\.motionPolicy) private var motionPolicy

    public init(
        value: Double,
        format: @escaping (Double) -> String = { String(format: "%.0f", $0) },
        font: Font = Instrument.Typography.display,
        unit: String? = nil,
        unitFont: Font = Instrument.Typography.unit
    ) {
        self.value = value
        self.format = format
        self.font = font
        self.unit = unit
        self.unitFont = unitFont
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
    }

    @ViewBuilder
    private var numberView: some View {
        let text = format(value)

        if #available(macOS 14.0, *) {
            if motionPolicy == .full {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
                    .contentTransition(.numericText(value: value))
                    .animation(Motion.value(), value: value)
            } else if motionPolicy == .reduced {
                Text(text)
                    .font(font)
                    .tracking(opticalTracking)
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
        let formatted = format(value)
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
