import SwiftUI

/// Borderless glass card container for panel content sections (ADR 0009 / Task 8.5.7 Kit v2).
/// Specifications:
/// - Background: `Instrument.Surface.module`
/// - Corner radius: `Instrument.Radius.module` (12 pt)
/// - Padding: `Instrument.Space.modulePadding` (12 pt)
/// - Integrated sentence-case header (`11.5 pt` `.semibold`, `.secondary`) + optional trailing accessory inside the top of the card, `8 pt` above body content
/// - Invariant: Never nested. No strokes or borders (except Increased Contrast accessibility border).
public struct Section<Content: View, Trailing: View>: View {
    public let title: String?
    public let trailing: Trailing
    public let content: Content

    /// Compatibility accessor matching the v1 `Module.eyebrow` property name.
    public var eyebrow: String? { title }

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        _ title: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    public init(
        eyebrow: String?,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = eyebrow
        self.trailing = trailing()
        self.content = content()
    }

    private var showsHeader: Bool {
        title != nil || Trailing.self != EmptyView.self
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.m) {
                    if let title {
                        Text(title)
                            .font(Instrument.Typography.sectionTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                    }

                    Spacer(minLength: Instrument.Space.m)

                    trailing
                }
                .padding(.bottom, Instrument.Space.m)
            }

            VStack(alignment: .leading, spacing: Instrument.Space.stackSpacing) {
                content
            }
        }
        .padding(Instrument.Space.modulePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                .fill(Instrument.Surface.module)
        )
        .overlay {
            if colorSchemeContrast == .increased {
                RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1.0)
            } else {
                RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Instrument.Surface.edgeHighlight, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
    }
}

extension Section where Trailing == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.trailing = EmptyView()
        self.content = content()
    }

    public init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }

    public init(
        eyebrow: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = eyebrow
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// Source-compatible alias for all existing panel modules during Kit v2 migration.
public typealias Module = Section

#if DEBUG
struct Module_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Section("Processor Overview") {
                Text("Content inside section")
                    .font(Instrument.Typography.body)
            }

            Module(eyebrow: "Memory Composition") {
                Button("Action") {}
                    .buttonStyle(.plain)
            } content: {
                Text("Section with trailing accessory")
                    .font(Instrument.Typography.body)
            }
        }
        .padding()
        .frame(width: 320)
        .background(Instrument.Surface.panel)
    }
}
#endif
