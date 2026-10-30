import SwiftUI
import AppKit
import iStatsCore

// MARK: - Preferences Section Navigation

public enum PreferencesSection: String, CaseIterable, Identifiable, Sendable {
    case menuBar = "menuBar"
    case general = "general"
    case alerts = "alerts"
    case about = "about"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .general: return "General & Units"
        case .alerts: return "Notifications"
        case .about: return "About"
        }
    }

    public var icon: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .general: return "slider.horizontal.3"
        case .alerts: return "bell.badge"
        case .about: return "info.circle"
        }
    }

    public var shortcutNumber: KeyEquivalent {
        switch self {
        case .menuBar: return "1"
        case .general: return "2"
        case .alerts: return "3"
        case .about: return "4"
        }
    }
}

// MARK: - AppKit Translucent Sidebar Visual Effect

public struct SidebarVisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Modern Settings Card & Row Components

/// A sleek grouped card container matching macOS System Settings styling.
public struct SettingsCard<Content: View>: View {
    public let title: String?
    public let subtitle: String?
    @ViewBuilder public let content: () -> Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
        }
    }
}

/// A standardized setting row with icon/badge, title, description, and control trailing view.
public struct SettingsRow<Leading: View, Trailing: View>: View {
    public let leading: Leading
    public let title: String
    public let subtitle: String?
    public let trailing: Trailing

    public init(
        @ViewBuilder leading: () -> Leading,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A macOS-style tinted squircle icon badge.
public struct SettingsBadge: View {
    public let icon: String
    public let color: Color
    public let size: CGFloat

    public init(icon: String, color: Color = .accentColor, size: CGFloat = 26) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(color.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Category Tint & Icon Helpers

public func preferenceCategoryColor(for category: MetricCategory) -> Color {
    switch category {
    case .cpu: return .blue
    case .memory: return .green
    case .gpu: return .purple
    case .thermal: return .orange
    case .fan: return .cyan
    case .network: return .teal
    case .disk: return .indigo
    case .power: return .mint
    }
}

public func preferenceCategoryIcon(for category: MetricCategory) -> String {
    switch category {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .thermal: return "thermometer.medium"
    case .fan: return "fan"
    case .gpu: return "display"
    case .network: return "network"
    case .disk: return "internaldrive"
    case .power: return "bolt.fill"
    }
}

