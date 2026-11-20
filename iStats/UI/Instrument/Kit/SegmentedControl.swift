import SwiftUI
import iStatsCore

/// Unified glass-puck segmented control for Instrument panels (Task 8.5.7 Kit v2).
/// Used for `PageSwitcher` (`Now · Details · History`) and `HistoryPage` range selection (`1m · 5m · 15m`).
public struct SegmentedControl<Option: Hashable>: View {
    public let options: [Option]
    @Binding public var selection: Option
    public let label: (Option) -> String
    public let fontSize: CGFloat
    public let horizontalPadding: CGFloat
    public let verticalPadding: CGFloat
    public let accessibilityLabelProvider: ((Option) -> String)?

    @Namespace private var puckNamespace
    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        options: [Option],
        selection: Binding<Option>,
        fontSize: CGFloat = 11,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 3,
        accessibilityLabel: ((Option) -> String)? = nil,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.accessibilityLabelProvider = accessibilityLabel
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = (selection == option)
                let title = label(option)

                Button {
                    let animation: Animation? = switch motionPolicy {
                    case .full: Motion.snappy
                    case .reduced: .easeInOut(duration: 0.15)
                    case .frozen: nil
                    }
                    withAnimation(animation) {
                        selection = option
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            puckView
                        }

                        Text(title)
                            .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, verticalPadding)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabelProvider?(option) ?? title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    if colorSchemeContrast == .increased {
                        RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                            .stroke(Color.primary.opacity(0.28), lineWidth: 0.75)
                    }
                }
        )
    }

    @ViewBuilder
    private var puckView: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        colorSchemeContrast == .increased
                            ? Color.primary.opacity(0.35)
                            : Instrument.Surface.edgeHighlight,
                        lineWidth: 0.5
                    )
            )

        if motionPolicy == .full {
            shape.matchedGeometryEffect(id: "segmentedPuck", in: puckNamespace)
        } else {
            shape
        }
    }
}

#if DEBUG
struct SegmentedControl_Previews: PreviewProvider {
    private struct PreviewWrapper: View {
        @State private var range = "1m"
        var body: some View {
            SegmentedControl(
                options: ["1m", "5m", "15m"],
                selection: $range
            ) { $0 }
            .padding()
            .background(Instrument.Surface.panel)
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
#endif
