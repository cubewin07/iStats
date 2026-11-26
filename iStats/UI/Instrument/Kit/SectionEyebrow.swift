import SwiftUI
import iStatsCore

/// Section eyebrow title with optional glossary `InfoButton` and trailing accessory (ADR 0009 / Task 8.5 / Task 9.11).
/// Replaces legacy `Divider()` + `sectionTitle`.
public struct SectionEyebrow<Trailing: View>: View {
    public let title: String
    public let glossaryKey: MetricTerm?
    public let trailing: Trailing

    public init(
        _ title: String,
        glossaryKey: MetricTerm? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.glossaryKey = glossaryKey
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Instrument.Space.xs) {
            Text(title.uppercased())
                .font(Instrument.Typography.eyebrow)
                .tracking(0.6)
                .foregroundColor(.secondary)

            if let glossaryKey {
                InfoButton(term: glossaryKey)
            }

            Spacer()

            trailing
        }
        .frame(height: 16)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionEyebrow where Trailing == EmptyView {
    public init(_ title: String, glossaryKey: MetricTerm? = nil) {
        self.title = title
        self.glossaryKey = glossaryKey
        self.trailing = EmptyView()
    }
}

#if DEBUG
struct SectionEyebrow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Instrument.Space.l) {
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

