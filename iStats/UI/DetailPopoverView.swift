import SwiftUI
import iStatsCore

public struct DetailPopoverView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("iStats")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("v0.1.0")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            // Shell Content Placeholder
            VStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("System Monitor")
                    .font(.headline)
                Text("Phase 1 Foundation Shell active.\nMetric samplers (CPU, Memory, Network, Disk, Power, Thermals) will connect in upcoming phases.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            Divider()

            // Footer / Actions
            HStack {
                Text("Status: Ready")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
