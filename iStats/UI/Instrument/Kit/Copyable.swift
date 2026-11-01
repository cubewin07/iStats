import SwiftUI
import AppKit

/// Copyable view modifier that copies text to pasteboard on click,
/// morphing the view to "Copied ✓" for 1.2 s with VoiceOver announcement (ADR 0009 / Task 8.5).
public struct CopyableContentModifier: ViewModifier {
    public let textToCopy: String
    @State private var isCopied: Bool = false

    public init(textToCopy: String) {
        self.textToCopy = textToCopy
    }

    public func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isCopied ? 0.0 : 1.0)

            if isCopied {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Copied ✓")
                        .font(Instrument.Typography.micro)
                }
                .foregroundColor(.accentColor)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            copyAction()
        }
        .help("Click to copy: \(textToCopy)")
    }

    private func copyAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)

        withAnimation(Motion.snappy) {
            isCopied = true
        }

        let targetElement: Any = ((NSApp.keyWindow ?? NSApp.mainWindow) ?? NSApp) as Any
        NSAccessibility.post(
            element: targetElement,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "Copied \(textToCopy) to clipboard"]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(Motion.snappy) {
                isCopied = false
            }
        }
    }
}

public extension View {
    /// Enables click-to-copy on any view, morphing briefly to "Copied ✓" and posting VoiceOver announcement.
    func copyable(text: String) -> some View {
        self.modifier(CopyableContentModifier(textToCopy: text))
    }
}

#if DEBUG
struct Copyable_Previews: PreviewProvider {
    static var previews: some View {
        Text("192.168.1.104")
            .font(Instrument.Typography.value)
            .padding(8)
            .background(Instrument.Surface.module)
            .copyable(text: "192.168.1.104")
            .padding()
    }
}
#endif
