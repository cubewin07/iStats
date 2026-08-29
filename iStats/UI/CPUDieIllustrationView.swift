import SwiftUI
import iStatsCore

/// Live Apple Silicon / Intel silicon die matrix illustration (72×72 pt default, with thumbnail mode).
/// Features distinct E-core cells and P-core cells, filled proportionally to individual core loads.
public struct CPUDieIllustrationView: View {
    public let sample: CPUSample?
    public let size: CGFloat
    public let showLabels: Bool

    public init(sample: CPUSample?, size: CGFloat = 72, showLabels: Bool = true) {
        self.sample = sample
        self.size = size
        self.showLabels = showLabels
    }

    public var body: some View {
        ZStack {
            // Die substrate package
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.85),
                            Color(nsColor: .windowBackgroundColor).opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.35), Color.primary.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)

            if let s = sample, !s.perCore.isEmpty {
                dieContent(sample: s)
                    .padding(size * 0.08)
            } else {
                // Idle / Placeholder die
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.35))
                    .foregroundColor(.blue.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func dieContent(sample: CPUSample) -> some View {
        let eCount = sample.efficiencyCoreCount ?? 0
        let pCount = sample.performanceCoreCount ?? 0
        let hasTopology = eCount > 0 && pCount > 0 && sample.perCore.count >= (eCount + pCount)

        if hasTopology {
            appleSiliconTopology(sample: sample, eCount: eCount, pCount: pCount)
        } else {
            uniformGrid(sample: sample)
        }
    }

    // MARK: - Apple Silicon Layout (E-cores on top/left, P-cores below/right)

    private func appleSiliconTopology(sample: CPUSample, eCount: Int, pCount: Int) -> some View {
        VStack(spacing: size * 0.04) {
            // E-Cores row (smaller cells)
            HStack(spacing: size * 0.03) {
                if showLabels && size >= 50 {
                    Text("E")
                        .font(.system(size: size * 0.11, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                }

                ForEach(0..<eCount, id: \.self) { i in
                    let load = i < sample.perCore.count ? sample.perCore[i] : 0.0
                    coreCell(load: load, isP: false)
                }
            }
            .frame(maxHeight: .infinity)

            // P-Cores row (larger cells)
            HStack(spacing: size * 0.03) {
                if showLabels && size >= 50 {
                    Text("P")
                        .font(.system(size: size * 0.11, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.9))
                }

                let pGridColumns = min(pCount, 8)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: size * 0.03), count: pGridColumns), spacing: size * 0.03) {
                    ForEach(0..<pCount, id: \.self) { i in
                        let coreIdx = eCount + i
                        let load = coreIdx < sample.perCore.count ? sample.perCore[coreIdx] : 0.0
                        coreCell(load: load, isP: true)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Uniform Grid Layout (Intel / Standard Macs)

    private func uniformGrid(sample: CPUSample) -> some View {
        let total = min(sample.perCore.count, 24)
        let cols = total <= 4 ? 2 : (total <= 8 ? 4 : (total <= 16 ? 4 : 6))

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: size * 0.04), count: cols), spacing: size * 0.04) {
            ForEach(0..<total, id: \.self) { i in
                let load = sample.perCore[i]
                coreCell(load: load, isP: true)
            }
        }
    }

    // MARK: - Single Core Cell

    private func coreCell(load: Double, isP: Bool) -> some View {
        GeometryReader { geo in
            let fillHeight = geo.size.height * CGFloat(min(max(load / 100.0, 0.05), 1.0))

            ZStack(alignment: .bottom) {
                // Background cell well
                RoundedRectangle(cornerRadius: size * 0.04)
                    .fill(Color.primary.opacity(0.08))

                // Active load fill
                RoundedRectangle(cornerRadius: size * 0.04)
                    .fill(
                        LinearGradient(
                            colors: isP
                                ? [Color.blue, Color.cyan]
                                : [Color.teal, Color.cyan.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: fillHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.04)
                    .strokeBorder(Color.blue.opacity(load > 70 ? 0.8 : 0.2), lineWidth: 0.5)
            )
        }
    }
}
