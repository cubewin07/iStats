import SwiftUI

/// Compact 2-column or 2x2 grid container for telemetry metric cards.
public struct StatGrid<Content: View>: View {
    public let columns: Int
    public let content: () -> Content

    public init(columns: Int = 2, @ViewBuilder content: @escaping () -> Content) {
        self.columns = columns
        self.content = content
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.sm), count: columns),
            spacing: Tokens.sm
        ) {
            content()
        }
    }
}

#Preview("StatGrid") {
    StatGrid(columns: 2) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Read Rate").font(Tokens.bodyLabel).foregroundColor(.secondary)
            Text("42.8 MB/s").font(Tokens.monoValue)
        }
        .padding(8)
        .cardBackground()

        VStack(alignment: .leading, spacing: 2) {
            Text("Write Rate").font(Tokens.bodyLabel).foregroundColor(.secondary)
            Text("12.4 MB/s").font(Tokens.monoValue)
        }
        .padding(8)
        .cardBackground()

        VStack(alignment: .leading, spacing: 2) {
            Text("Read IOPS").font(Tokens.bodyLabel).foregroundColor(.secondary)
            Text("1,420 ops/s").font(Tokens.monoValue)
        }
        .padding(8)
        .cardBackground()

        VStack(alignment: .leading, spacing: 2) {
            Text("Write IOPS").font(Tokens.bodyLabel).foregroundColor(.secondary)
            Text("680 ops/s").font(Tokens.monoValue)
        }
        .padding(8)
        .cardBackground()
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}
