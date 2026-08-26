import SwiftUI
import iStatsCore

public struct DetailPopoverView: View {
    @State private var memorySample: MemorySample?

    public init(memorySample: MemorySample? = nil) {
        self._memorySample = State(initialValue: memorySample)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            .padding(.bottom, 2)

            Divider()

            // Memory Monitoring & Pressure Alert Section
            MemorySummaryView(sample: memorySample)

            Divider()

            // Footer / Actions
            HStack {
                Text(memorySample != nil ? "Pressure: \(memorySample!.pressure.displayName)" : "Status: Ready")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Preferences...") {
                    PreferencesWindowController.shared.showPreferences()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if memorySample == nil {
                Task.detached(priority: .userInitiated) {
                    let sampler = MemorySampler()
                    if let sample = try? sampler.sample() {
                        await MainActor.run {
                            self.memorySample = sample
                        }
                    }
                }
            }
        }
    }
}
