import SwiftUI
import iStatsCore

// MARK: - Standard Popover Header

/// A unified header across all category popovers featuring the 3-tier hierarchy:
/// Category branding (icon/name) + Dad sentence + Semantic status badge (Green/Yellow/Orange/Red).
public struct PopoverHeaderView: View {
    public let category: MetricCategory
    public let title: String
    public let subtitle: String
    public let verdict: MetricVerdict

    public init(
        category: MetricCategory,
        title: String? = nil,
        subtitle: String? = nil,
        verdict: MetricVerdict
    ) {
        self.category = category
        self.title = title ?? Self.defaultTitle(for: category)
        self.subtitle = subtitle ?? verdict.dadSentence
        self.verdict = verdict
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Category Icon Badge with subtle accent tint glow
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(categoryColor(for: category).opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: iconName(for: category))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(categoryColor(for: category))
            }

            // Category Title + Dad Human Sentence
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Human Status Badge (Semantic Status Colors: Green, Yellow, Orange, Red)
            HStack(spacing: 4.5) {
                Circle()
                    .fill(verdict.level.color)
                    .frame(width: 6, height: 6)

                Text(verdict.badgeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(verdict.level.color)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(verdict.level.color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(verdict.level.color.opacity(0.25), lineWidth: 0.5)
            )
        }
        .padding(.bottom, 2)
    }

    private static func defaultTitle(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .thermal: return "Thermals"
        case .fan: return "Fans"
        case .network: return "Network"
        case .disk: return "Disk Storage"
        case .power: return "Battery & Power"
        }
    }

    private func categoryColor(for category: MetricCategory) -> Color {
        switch category {
        case .cpu: return .blue
        case .memory: return .green
        case .gpu: return .purple
        case .thermal: return .orange
        case .fan: return .cyan
        case .network: return .teal
        case .disk: return .indigo
        case .power: return .green
        }
    }

    private func iconName(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .fan: return "fan"
        case .gpu: return "display"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        }
    }
}

// MARK: - Collapsible Disclosure Section

/// A standardized progressive disclosure container for diagnostic details.
public struct CollapsibleSection<Content: View>: View {
    public let title: String
    public let count: Int?
    @Binding public var isExpanded: Bool
    @ViewBuilder public let content: () -> Content

    public init(
        title: String = "More details",
        count: Int? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.primary)

                    if let count = count, count > 0 {
                        Text("(\(count))")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Dual-Trace Rolling Graph View

/// High-performance dual-trace rolling sparkline for bidirectional Network or Disk I/O.
public struct DualTraceRollingGraphView: View {
    public let primaryValues: [Double]
    public let secondaryValues: [Double]
    public let primaryColor: Color
    public let secondaryColor: Color
    public let primaryLabel: String
    public let secondaryLabel: String
    public let height: CGFloat
    public let capacity: Int

    public init(
        primaryValues: [Double],
        secondaryValues: [Double],
        primaryColor: Color = .teal,
        secondaryColor: Color = .blue,
        primaryLabel: String = "In",
        secondaryLabel: String = "Out",
        height: CGFloat = 44,
        capacity: Int = 60
    ) {
        self.primaryValues = primaryValues
        self.secondaryValues = secondaryValues
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.height = height
        self.capacity = max(capacity, 2)
    }

    private var maxValue: Double {
        let max1 = primaryValues.max() ?? 0.0
        let max2 = secondaryValues.max() ?? 0.0
        return max(max1, max2, 1.0)
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                )

            // Grid lines
            VStack(spacing: 0) {
                Divider().opacity(0.06)
                Spacer()
                Divider().opacity(0.08)
                Spacer()
                Divider().opacity(0.06)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                let pts1 = calculatePoints(values: primaryValues, width: w, height: h, maxVal: maxValue)
                let pts2 = calculatePoints(values: secondaryValues, width: w, height: h, maxVal: maxValue)

                // Secondary trace fill & line (e.g. Upload)
                if pts2.count >= 2 {
                    strokePath(points: pts2)
                        .stroke(secondaryColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                }

                // Primary trace fill & line (e.g. Download)
                if pts1.count >= 2 {
                    fillPath(points: pts1, height: h)
                        .fill(
                            LinearGradient(
                                colors: [primaryColor.opacity(0.25), primaryColor.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    strokePath(points: pts1)
                        .stroke(primaryColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .padding(3)
        }
        .frame(height: height)
        .clipped()
    }

    private func calculatePoints(values: [Double], width: CGFloat, height: CGFloat, maxVal: Double) -> [CGPoint] {
        guard !values.isEmpty, width > 0, height > 0 else { return [] }
        let count = values.count
        let stepX = width / CGFloat(max(capacity - 1, 1))
        let startX = width - (CGFloat(count - 1) * stepX)

        var points: [CGPoint] = []
        points.reserveCapacity(count)

        for (index, val) in values.enumerated() {
            let clamped = min(max(val, 0.0), maxVal)
            let normalized = CGFloat(clamped / maxVal)
            let x = startX + CGFloat(index) * stepX
            let y = height - (normalized * (height - 4)) - 2
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    private func strokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for pt in points.dropFirst() {
            path.addLine(to: pt)
        }
        return path
    }

    private func fillPath(points: [CGPoint], height: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: height))
        path.addLine(to: first)
        for pt in points.dropFirst() {
            path.addLine(to: pt)
        }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.closeSubpath()
        return path
    }
}
