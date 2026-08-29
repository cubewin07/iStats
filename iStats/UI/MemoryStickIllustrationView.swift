import SwiftUI
import iStatsCore

/// Live stratified RAM stick illustration featuring the 5 distinct memory composition layers:
/// Apps (Blue) -> Wired/System (Purple) -> Compressed/Squeezed (Orange) -> Cached/Reusable (Light Gray) -> Free (Empty).
public struct MemoryStickIllustrationView: View {
    public let sample: MemorySample?
    public let height: CGFloat
    public let width: CGFloat
    public let showLabels: Bool

    public init(
        sample: MemorySample?,
        height: CGFloat = 72,
        width: CGFloat = 34,
        showLabels: Bool = true
    ) {
        self.sample = sample
        self.height = height
        self.width = width
        self.showLabels = showLabels
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Vertical RAM Stick
            ZStack(alignment: .bottom) {
                // PCB Module Body
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor).opacity(0.85),
                                Color(nsColor: .windowBackgroundColor).opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                if let s = sample, s.total > 0 {
                    layersView(sample: s)
                }

                // Golden Contact Pins at bottom
                VStack {
                    Spacer()
                    HStack(spacing: 1.5) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.yellow.opacity(0.75))
                                .frame(width: 2, height: 3)
                        }
                    }
                    .padding(.bottom, 1)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)

            // Optional 5-layer legend beside the stick
            if showLabels && width >= 30 {
                VStack(alignment: .leading, spacing: 2.5) {
                    legendItem(label: "Free", color: Color.secondary.opacity(0.35))
                    legendItem(label: "Reusable", color: Color.secondary.opacity(0.6))
                    legendItem(label: "Squeezed", color: Color.orange)
                    legendItem(label: "System", color: Color.purple)
                    legendItem(label: "Apps", color: Color.blue)
                }
                .font(.system(size: 8.5, weight: .medium))
            }
        }
    }

    @ViewBuilder
    private func layersView(sample: MemorySample) -> some View {
        let total = Double(sample.total)
        let app = Double(sample.appMemory ?? (sample.used >= (sample.wired + sample.compressed) ? sample.used - sample.wired - sample.compressed : sample.used))
        let wired = Double(sample.wired)
        let compressed = Double(sample.compressed)
        let cached = Double(sample.cached)
        let free = Double(sample.free)

        // Normalize fractions
        let sum = max(total, app + wired + compressed + cached + free)
        let appFrac = app / sum
        let wiredFrac = wired / sum
        let compFrac = compressed / sum
        let cachedFrac = cached / sum
        let freeFrac = max(0.0, 1.0 - appFrac - wiredFrac - compFrac - cachedFrac)

        VStack(spacing: 0.5) {
            // Layer 5: Free (Top)
            Rectangle()
                .fill(Color.clear)
                .frame(height: max(0, height * CGFloat(freeFrac)))

            // Layer 4: Cached Files (Reusable - Light Gray striped/translucent)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.28), Color.secondary.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: max(0, height * CGFloat(cachedFrac)))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

            // Layer 3: Compressed (Squeezed - Orange)
            Rectangle()
                .fill(Color.orange.opacity(0.9))
                .frame(height: max(0, height * CGFloat(compFrac)))

            // Layer 2: Wired (System - Purple)
            Rectangle()
                .fill(Color.purple.opacity(0.9))
                .frame(height: max(0, height * CGFloat(wiredFrac)))

            // Layer 1: App Memory (Apps - Blue)
            Rectangle()
                .fill(Color.blue.opacity(0.95))
                .frame(height: max(0, height * CGFloat(appFrac)))
        }
    }

    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .foregroundColor(.secondary)
        }
    }
}
