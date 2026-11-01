import SwiftUI

/// Section eyebrow title with optional trailing accessory (ADR 0009 / Task 8.5).
/// Replaces legacy `Divider()` + `sectionTitle`.
public struct SectionEyebrow<Trailing: View>: View {
    public let title: String
    public let trailing: Trailing

    public init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Instrument.Typography.eyebrow)
                .tracking(0.6)
                .foregroundColor(.secondary)

            Spacer()

            trailing
        }
        .frame(height: 16)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionEyebrow where Trailing == EmptyView {
    public init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

#if DEBUG
struct SectionEyebrow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            SectionEyebrow("CORES & CLUSTERS")
            SectionEyebrow("TOP PROCESSES") {
                Button("Show All") {}
                    .buttonStyle(.plain)
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .frame(width: 300)
        .background(Instrument.Surface.panel)
    }
}
#endif
