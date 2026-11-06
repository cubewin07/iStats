import SwiftUI

/// Standard empty or unavailable state for instrument modules and tabs (ADR 0009 / Task 8.5).
public struct InsetEmptyState<ActionView: View>: View {
    public let systemImage: String
    public let title: String
    public let reason: String
    public let action: ActionView

    public init(
        systemImage: String,
        title: String,
        reason: String,
        @ViewBuilder action: () -> ActionView
    ) {
        self.systemImage = systemImage
        self.title = title
        self.reason = reason
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 44 pt Surface.inset circle with 22 pt symbol
            ZStack {
                Circle()
                    .fill(Instrument.Surface.inset)
                    .frame(width: 44, height: 44)

                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(Instrument.Typography.headline)
                    .foregroundColor(.primary)

                Text(reason)
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            action
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(reason)")
    }
}

extension InsetEmptyState where ActionView == EmptyView {
    public init(
        systemImage: String,
        title: String,
        reason: String
    ) {
        self.systemImage = systemImage
        self.title = title
        self.reason = reason
        self.action = EmptyView()
    }
}

#if DEBUG
struct InsetEmptyState_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            InsetEmptyState(
                systemImage: "fan.slash",
                title: "No Fans Detected",
                reason: "This Mac has a fanless passive cooling design."
            )

            InsetEmptyState(
                systemImage: "battery.slash",
                title: "No Battery Present",
                reason: "Desktop Mac running exclusively on AC line power."
            ) {
                Button("Learn More") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 320)
        .background(Instrument.Surface.panel)
    }
}
#endif

