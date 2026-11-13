import SwiftUI
import iStatsCore

/// Unified capsule filter chip for channel isolation and thermal source selection (Task 8.5.7 Kit v2).
public struct FilterChip: View {
    public let title: String
    public let isSelected: Bool
    public let isDimmed: Bool
    public let dotColor: Color?
    public let tint: Color
    public let fontSize: CGFloat
    public let action: () -> Void

    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        title: String,
        isSelected: Bool,
        isDimmed: Bool = false,
        dotColor: Color? = nil,
        tint: Color = .accentColor,
        fontSize: CGFloat = 10.5,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.dotColor = dotColor
        self.tint = tint
        self.fontSize = fontSize
        self.action = action
    }

    public var body: some View {
        Button {
            let animation: Animation? = switch motionPolicy {
            case .full: Motion.snappy
            case .reduced: .easeInOut(duration: 0.15)
            case .frozen: nil
            }
            withAnimation(animation) {
                action()
            }
        } label: {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                }

                Text(title)
                    .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(labelColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(isSelected ? tint.opacity(0.16) : Color.primary.opacity(0.05))
                    .overlay(
                        Capsule()
                            .stroke(strokeColor, lineWidth: isSelected ? 1.0 : 0.5)
                    )
            )
            .opacity(isDimmed ? 0.45 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var labelColor: Color {
        if isSelected {
            return .primary
        }
        if isDimmed {
            return .secondary.opacity(0.45)
        }
        return .secondary
    }

    private var strokeColor: Color {
        if isSelected {
            return tint.opacity(colorSchemeContrast == .increased ? 0.85 : 0.48)
        }
        return colorSchemeContrast == .increased ? Color.primary.opacity(0.25) : Color.clear
    }
}

#if DEBUG
struct FilterChip_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 6) {
            FilterChip(title: "User", isSelected: true, dotColor: .blue, tint: .blue) {}
            FilterChip(title: "System", isSelected: false, isDimmed: true, dotColor: .orange, tint: .orange) {}
            FilterChip(title: "Peak", isSelected: true, tint: .orange) {}
            FilterChip(title: "CPU", isSelected: false, tint: .orange) {}
        }
        .padding()
        .background(Instrument.Surface.panel)
    }
}
#endif
