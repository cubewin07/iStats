import SwiftUI
import iStatsCore

/// Live dual dynamic network pipes illustration.
/// Stroke thickness dynamically maps to download (Teal) and upload (Blue) rates:
/// Idle = hairline; fast traffic = fat pipe.
public struct NetworkPipesIllustrationView: View {
    public let sample: NetworkSample?
    public let size: CGSize

    public init(sample: NetworkSample?, size: CGSize = CGSize(width: 44, height: 68)) {
        self.sample = sample
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Background container
            RoundedRectangle(cornerRadius: 6)
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
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.teal.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)

            HStack(spacing: 10) {
                // Download Pipe (Teal, Arrow Down)
                pipeBar(
                    rate: sample?.totalBytesInPerSec ?? 0.0,
                    color: .teal,
                    isDown: true
                )

                // Upload Pipe (Blue, Arrow Up)
                pipeBar(
                    rate: sample?.totalBytesOutPerSec ?? 0.0,
                    color: .blue,
                    isDown: false
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: size.width, height: size.height)
    }

    private func pipeBar(rate: Double, color: Color, isDown: Bool) -> some View {
        // Map rate (0 to 25 MB/s) to stroke width (2pt to 10pt)
        let strokeWidth = CGFloat(calculatePipeThickness(bytesPerSec: rate))

        return VStack(spacing: 2) {
            if isDown {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color)
            }

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.65)],
                        startPoint: isDown ? .top : .bottom,
                        endPoint: isDown ? .bottom : .top
                    )
                )
                .frame(width: strokeWidth)
                .frame(maxHeight: .infinity)
                .shadow(color: color.opacity(rate > 100_000 ? 0.4 : 0.0), radius: 2)

            if !isDown {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color)
            }
        }
    }

    private func calculatePipeThickness(bytesPerSec: Double) -> Double {
        if bytesPerSec <= 10_000 {
            return 2.0 // Hairline for idle
        } else if bytesPerSec <= 200_000 {
            return 3.5
        } else if bytesPerSec <= 1_000_000 {
            return 5.5
        } else if bytesPerSec <= 10_000_000 {
            return 8.0
        } else {
            return 11.0 // Fat pipe
        }
    }
}
