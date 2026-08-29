import SwiftUI
import iStatsCore

/// Live storage tank reservoir illustration for the primary boot volume.
/// Uses semantic coloring based on storage fill:
/// <85% Indigo | 85-95% Orange ("Getting full") | >=95% Red ("Almost full").
public struct DiskStorageTankIllustrationView: View {
    public let sample: DiskSample?
    public let byteStandard: Units.ByteUnitStandard
    public let width: CGFloat
    public let height: CGFloat

    public init(
        sample: DiskSample?,
        byteStandard: Units.ByteUnitStandard = .iec,
        width: CGFloat = 40,
        height: CGFloat = 68
    ) {
        self.sample = sample
        self.byteStandard = byteStandard
        self.width = width
        self.height = height
    }

    private var bootVolume: VolumeCapacity? {
        sample?.volumes.first(where: { $0.mountPoint == "/" }) ?? sample?.volumes.first
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Tank Body Frame
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
                        .strokeBorder(tankColor.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)

            if let vol = bootVolume, vol.total > 0 {
                let usedRatio = Double(vol.used) / Double(vol.total)
                let fillHeight = height * CGFloat(min(max(usedRatio, 0.05), 1.0))

                // Liquid fill level
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [tankColor, tankColor.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: fillHeight)
                    .padding(2)

                // Measurement tick lines on side
                VStack {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 4, height: 1)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 3)
                .padding(.vertical, 6)
            }

            // Drive Icon in center
            Image(systemName: "internaldrive.fill")
                .font(.system(size: width * 0.4))
                .foregroundColor(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .padding(.bottom, height * 0.1)
        }
        .frame(width: width, height: height)
    }

    private var tankColor: Color {
        guard let vol = bootVolume, vol.total > 0 else { return .indigo }
        let usedRatio = (Double(vol.used) / Double(vol.total)) * 100.0
        if usedRatio >= 95.0 {
            return .red
        } else if usedRatio >= 85.0 {
            return .orange
        } else {
            return .indigo
        }
    }
}
