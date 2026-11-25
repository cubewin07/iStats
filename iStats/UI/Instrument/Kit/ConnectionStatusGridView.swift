import SwiftUI
import AppKit
import iStatsCore

/// Color-coded Connection Status Grid for the Network Details panel.
///
/// Displays:
/// 1. A live status badge (Green = Connected, Yellow = Bad Connection, Red = Not Connected).
/// 2. A 3×20 (60-cell) chronological timeline grid where each cell reflects actual verified
///    connectivity (path state + active packet reachability + latency/loss/signal quality).
/// 3. A 2×2 diagnostic status grid explaining *why* (Route, Internet RTT, Packet Loss, Link Quality).
public struct ConnectionStatusGridView: View {
    public let health: NetworkConnectionHealth
    public let history: [ConnectionStatusPoint]
    public let primaryInterface: String?
    public let primaryType: NetworkConnectionType?
    public let wifiDetails: WiFiLinkTelemetry?

    @State private var hoveredPoint: ConnectionStatusPoint?
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public static let gridColumns: Int = 20
    public static let gridRows: Int = 3
    public static let totalSlots: Int = gridColumns * gridRows

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    public init(
        health: NetworkConnectionHealth,
        history: [ConnectionStatusPoint],
        primaryInterface: String? = nil,
        primaryType: NetworkConnectionType? = nil,
        wifiDetails: WiFiLinkTelemetry? = nil
    ) {
        self.health = health
        self.history = history
        self.primaryInterface = primaryInterface
        self.primaryType = primaryType
        self.wifiDetails = wifiDetails
    }

    // MARK: - Traffic-Light Palette

    /// Vibrant Display P3 fill color for grid cells (Green / Yellow / Red).
    public static func cellColor(for status: NetworkConnectionStatus) -> Color {
        switch status {
        case .connected:
            return CategoryPalette.dynamicColor(lightHex: "#22A355", darkHex: "#4ADE80")
        case .degraded:
            return CategoryPalette.dynamicColor(lightHex: "#D99B00", darkHex: "#FFC53D")
        case .disconnected:
            return CategoryPalette.dynamicColor(lightHex: "#DC2626", darkHex: "#FF5C5C")
        }
    }

    /// WCAG AA contrast text/badge color for status labels.
    public static func badgeTextColor(for status: NetworkConnectionStatus) -> Color {
        CategoryPalette.statusColor(for: status.statusLevel)
    }

    /// Fixed-length slot array aligned to the right (newest check at the final slot).
    internal var gridSlots: [ConnectionStatusPoint?] {
        let recent = Array(history.suffix(Self.totalSlots))
        let emptyCount = max(0, Self.totalSlots - recent.count)
        return Array(repeating: nil, count: emptyCount) + recent.map { Optional($0) }
    }

    private var headerTitle: String {
        if let point = hoveredPoint {
            let time = Self.timeFormatter.string(from: point.timestamp)
            return "\(point.status.displayName) · \(time)"
        }
        return "Connection Status"
    }

    private var connectedPercent: Int? {
        guard !history.isEmpty else { return nil }
        let okCount = history.filter { $0.status == .connected }.count
        return Int(round((Double(okCount) / Double(history.count)) * 100.0))
    }

    public var body: some View {
        Section(
            headerTitle,
            trailing: {
                statusBadge
            }
        ) {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Diagnostic summary line (or hovered cell detail)
                HStack(spacing: Instrument.Space.s) {
                    Text(hoveredPoint?.reason ?? health.reason)
                        .font(Instrument.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if let pct = connectedPercent {
                        Text("\(pct)% stable")
                            .font(Instrument.Typography.micro)
                            .foregroundStyle(.tertiary)
                    }
                }

                // 3×20 Connection Status Grid
                timelineGrid

                // Legend row
                HStack(spacing: 10) {
                    legendItem(color: Self.cellColor(for: .connected), label: "Connected")
                    legendItem(color: Self.cellColor(for: .degraded), label: "Bad")
                    legendItem(color: Self.cellColor(for: .disconnected), label: "Not Connected")
                    Spacer(minLength: 0)
                    Text("\(min(history.count, Self.totalSlots))/\(Self.totalSlots)")
                        .font(Instrument.Typography.micro)
                        .foregroundStyle(.tertiary)
                }

                Rectangle()
                    .fill(Instrument.Surface.hairline)
                    .frame(height: 0.5)

                // 2×2 Diagnostic Status Tiles
                diagnosticTileGrid
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connection Status")
        .accessibilityValue("\(health.status.displayName), \(health.reason)")
    }

    // MARK: - Live Status Pill

    private var statusBadge: some View {
        let isProbing = health.isProbing
        let textColor: Color = isProbing ? .secondary : Self.badgeTextColor(for: health.status)
        let dotColor: Color = isProbing ? .secondary : Self.cellColor(for: health.status)
        let label = isProbing ? "Checking…" : health.status.displayName

        return HStack(spacing: Instrument.Space.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(Instrument.Typography.eyebrow)
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(dotColor.opacity(colorSchemeContrast == .increased ? 0.22 : 0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            dotColor.opacity(colorSchemeContrast == .increased ? 0.65 : 0.24),
                            lineWidth: colorSchemeContrast == .increased ? 0.75 : 0.5
                        )
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(label)
    }

    // MARK: - 3×20 Timeline Status Grid

    private var timelineGrid: some View {
        let slots = gridSlots
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 8), spacing: 3),
            count: Self.gridColumns
        )
        let lastFilledIndex = slots.lastIndex(where: { $0 != nil })

        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<slots.count, id: \.self) { index in
                let point = slots[index]
                let isLatest = (index == lastFilledIndex)
                gridCell(point: point, isLatest: isLatest)
            }
        }
        .padding(Instrument.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                .fill(Instrument.Surface.inset.opacity(0.55))
        )
    }

    @ViewBuilder
    private func gridCell(point: ConnectionStatusPoint?, isLatest: Bool) -> some View {
        let isHovered = (point != nil && hoveredPoint?.id == point?.id)
        let fillColor: Color = point.map { Self.cellColor(for: $0.status) } ?? Instrument.Surface.inset

        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fillColor)
            .aspectRatio(1.0, contentMode: .fit)
            .overlay {
                if isHovered || isLatest {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isHovered ? 0.75 : 0.35),
                            lineWidth: isHovered ? 1.25 : 0.75
                        )
                } else if point != nil && colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5)
                }
            }
            .onHover { hovering in
                if hovering {
                    hoveredPoint = point
                } else if hoveredPoint?.id == point?.id {
                    hoveredPoint = nil
                }
            }
            .accessibilityLabel(point.map { "\($0.status.displayName), \($0.reason)" } ?? "No sample")
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: Instrument.Space.xs) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(Instrument.Typography.micro)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 2×2 Diagnostic Status Grid

    private var diagnosticTileGrid: some View {
        let columns = [
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.m),
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.m)
        ]

        // 1. Route tile
        let routeStatus: NetworkConnectionStatus = health.isPathSatisfied ? .connected : .disconnected
        let routeValue: String = {
            guard health.isPathSatisfied else { return "No Route" }
            if let iface = primaryInterface {
                let typeLabel = primaryType?.displayName ?? NetworkConnectionType.infer(from: iface).displayName
                return "\(typeLabel) (\(iface))"
            }
            return "Active"
        }()

        // 2. Internet / RTT tile
        let internetStatus: NetworkConnectionStatus = {
            if !health.isPathSatisfied || health.isInternetReachable == false {
                return .disconnected
            }
            if let rtt = health.latencyMs, rtt >= NetworkConnectionThresholds.degradedLatencyMs {
                return .degraded
            }
            if let jitter = health.jitterMs, jitter >= NetworkConnectionThresholds.degradedJitterMs {
                return .degraded
            }
            return .connected
        }()
        let internetValue: String = {
            if !health.isPathSatisfied || health.isInternetReachable == false {
                return "Unreachable"
            }
            if health.isProbing {
                return "Checking…"
            }
            if let rtt = health.latencyMs {
                return "\(Int(round(rtt))) ms"
            }
            return "Reachable"
        }()

        // 3. Packet Loss tile
        let lossStatus: NetworkConnectionStatus = {
            if !health.isPathSatisfied || health.isInternetReachable == false || health.packetLossPercent >= 100.0 {
                return .disconnected
            }
            if health.packetLossPercent >= NetworkConnectionThresholds.degradedPacketLossPercent
                || health.interfaceErrorDelta >= NetworkConnectionThresholds.degradedInterfaceErrorCount {
                return .degraded
            }
            return .connected
        }()
        let lossValue: String = {
            if !health.isPathSatisfied || health.isInternetReachable == false {
                return "100%"
            }
            if health.isProbing {
                return "—"
            }
            return "\(Int(round(health.packetLossPercent)))%"
        }()

        // 4. Link / Signal tile
        let linkStatus: NetworkConnectionStatus = {
            if !health.isPathSatisfied { return .disconnected }
            if let wifi = wifiDetails {
                if let pct = wifi.signalPercent, pct < NetworkConnectionThresholds.weakWiFiSignalPercent {
                    return .degraded
                }
                if wifi.qualityRating == "Weak" { return .degraded }
                if let snr = wifi.snr, snr < NetworkConnectionThresholds.weakWiFiSNR { return .degraded }
            }
            if health.isConstrained { return .degraded }
            return .connected
        }()
        let linkValue: String = {
            if !health.isPathSatisfied { return "Offline" }
            if let wifi = wifiDetails {
                if let pct = wifi.signalPercent {
                    return "\(wifi.qualityRating ?? "Wi-Fi") (\(pct)%)"
                }
                return wifi.qualityRating ?? "Wi-Fi"
            }
            if primaryType == .ethernet { return "Wired" }
            if primaryType == .vpn { return "VPN" }
            return health.isConstrained ? "Constrained" : "Normal"
        }()

        return LazyVGrid(columns: columns, spacing: Instrument.Space.s) {
            diagnosticTile(label: "Route", value: routeValue, status: routeStatus, isNeutral: false)
            diagnosticTile(label: "Internet", value: internetValue, status: internetStatus, isNeutral: health.isProbing)
            diagnosticTile(label: "Packet Loss", value: lossValue, status: lossStatus, isNeutral: health.isProbing)
            diagnosticTile(label: "Link", value: linkValue, status: linkStatus, isNeutral: false)
        }
    }

    private func diagnosticTile(
        label: String,
        value: String,
        status: NetworkConnectionStatus,
        isNeutral: Bool
    ) -> some View {
        let dotColor: Color = isNeutral ? .secondary : Self.cellColor(for: status)

        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(label)
                .font(Instrument.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(value)
                .font(Instrument.Typography.value)
                .foregroundColor(isNeutral ? .secondary : (status == .connected ? .primary : Self.badgeTextColor(for: status)))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.chip, style: .continuous)
                .fill(Instrument.Surface.inset.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
