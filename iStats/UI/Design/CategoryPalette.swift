import SwiftUI
import AppKit
import iStatsCore

/// Single source of truth for category identity colors and metric series palettes.
public enum CategoryPalette {
    /// Canonical SwiftUI identity color for each metric category.
    public static func color(for category: MetricCategory) -> Color {
        switch category {
        case .cpu: return .blue
        case .memory: return .mint
        case .gpu: return .purple
        case .thermal: return .orange
        case .fan: return .cyan
        case .network: return .indigo
        case .disk: return .teal
        case .power: return .pink
        }
    }

    /// Canonical AppKit identity color for menu bar renderers and CoreGraphics surfaces.
    public static func nsColor(for category: MetricCategory) -> NSColor {
        switch category {
        case .cpu: return .systemBlue
        case .memory: return .systemMint
        case .gpu: return .systemPurple
        case .thermal: return .systemOrange
        case .fan: return .systemCyan
        case .network: return .systemIndigo
        case .disk: return .systemTeal
        case .power: return .systemPink
        }
    }

    // MARK: - Dual Channel Series Colors
    public enum Series {
        // Network
        public static let networkDownload = Color.indigo
        public static let networkUpload = Color.pink.opacity(0.85)

        // Disk
        public static let diskRead = Color.teal
        public static let diskWrite = Color.orange.opacity(0.85)

        // CPU
        public static let cpuUser = Color.blue
        public static let cpuSystem = Color.red.opacity(0.70)

        // Memory composition
        public static let memoryApp = Color.mint
        public static let memoryWired = Color.mint.opacity(0.70)
        public static let memoryCompressed = Color.mint.opacity(0.45)
        public static let memoryCached = Color.mint.opacity(0.25)
    }

    // MARK: - Semantic Status Severity Colors
    public static func statusColor(for level: StatusLevel) -> Color {
        switch level {
        case .fine: return .green
        case .elevated: return .yellow
        case .warning: return .orange
        case .critical: return .red
        }
    }

    public static func statusNSColor(for level: StatusLevel) -> NSColor {
        switch level {
        case .fine: return .systemGreen
        case .elevated: return .systemYellow
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
