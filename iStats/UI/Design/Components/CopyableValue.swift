import SwiftUI
import AppKit

/// A key-value row where the value can be clicked to copy to clipboard with instant visual confirmation.
public struct CopyableValue: View {
    public let label: String
    public let value: String
    @State private var isCopied: Bool = false

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: Tokens.sm) {
            Text(label)
                .font(Tokens.bodyLabel)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Text(value)
                        .font(Tokens.monoValue)
                        .foregroundColor(.primary)

                    if isCopied {
                        Text("Copied")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). Click to copy.")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}

#Preview("CopyableValue") {
    VStack(spacing: 8) {
        CopyableValue(label: "IP Address", value: "192.168.1.145")
        CopyableValue(label: "Router Gateway", value: "192.168.1.1")
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}

