import SwiftUI

/// Borderless glass container for panel content modules (ADR 0009 / Task 8.5).
/// Specifications:
/// - Background: `Instrument.Surface.module`
/// - Corner radius: `Instrument.Radius.module` (12 pt)
/// - Padding: `Instrument.Space.modulePadding` (12 pt)
/// - Optional `eyebrow` placed ABOVE (outside) the module
/// - Hover state with subtle lift and tint
/// - Invariant: Never nested. No strokes or borders.
public struct Module<Content: View, Trailing: View>: View {
    public let eyebrow: String?
    public let trailing: Trailing
    public let content: Content

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        eyebrow: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.eyebrowGap) {
            if let eyebrow = eyebrow {
                SectionEyebrow(eyebrow) {
                    trailing
                }
            }

            VStack(alignment: .leading, spacing: Instrument.Space.stackSpacing) {
                content
            }
            .padding(Instrument.Space.modulePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                    .fill(Instrument.Surface.module)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                    .stroke(
                        colorSchemeContrast == .increased
                            ? Color.primary.opacity(0.35)
                            : Color.white.opacity(0.12),
                        lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.5
                    )
            )
        }
    }
}

extension Module where Trailing == EmptyView {
    public init(
        eyebrow: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.trailing = EmptyView()
        self.content = content()
    }
}

#if DEBUG
struct Module_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Module(eyebrow: "PROCESSOR OVERVIEW") {
                Text("Content inside module")
                    .font(Instrument.Typography.body)
            }

            Module(eyebrow: "MEMORY COMPOSITION") {
                Button("Action") {}
                    .buttonStyle(.plain)
            } content: {
                Text("Module with trailing accessory")
                    .font(Instrument.Typography.body)
            }
        }
        .padding()
        .frame(width: 320)
        .background(Instrument.Surface.panel)
    }
}
#endif
