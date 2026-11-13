import SwiftUI
import AppKit
import iStatsCore

/// Cached icon loader for process rows (Task 8.9 / Task 8.5.7 / fixes B12).
/// Caches both resolved icons and misses (non-app processes) so repeated renders never re-query AppKit on the main thread.
@MainActor
public final class ProcessIconCache {
    private enum CacheEntry {
        case icon(NSImage)
        case miss
    }

    public static let shared = ProcessIconCache()
    private var cache: [String: CacheEntry] = [:]
    private let maxEntries: Int
    private let resolver: (Int32) -> NSImage?

    internal init(
        maxEntries: Int = 512,
        resolver: @escaping (Int32) -> NSImage? = { pid in
            NSRunningApplication(processIdentifier: pid)?.icon
        }
    ) {
        self.maxEntries = maxEntries
        self.resolver = resolver
    }

    public func icon(for pid: Int32, bundleID: String?) -> NSImage? {
        let key = Self.cacheKey(pid: pid, bundleID: bundleID)
        if let entry = cache[key] {
            switch entry {
            case .icon(let image):
                return image
            case .miss:
                return nil
            }
        }

        if cache.count >= maxEntries {
            cache.removeAll(keepingCapacity: true)
        }

        if let icon = resolver(pid) {
            cache[key] = .icon(icon)
            return icon
        } else {
            cache[key] = .miss
            return nil
        }
    }

    internal func hasCachedEntry(for pid: Int32, bundleID: String?) -> Bool {
        cache[Self.cacheKey(pid: pid, bundleID: bundleID)] != nil
    }

    internal var cachedEntryCount: Int {
        cache.count
    }

    private static func cacheKey(pid: Int32, bundleID: String?) -> String {
        if let bundleID, !bundleID.isEmpty {
            return "bundle:\(bundleID)"
        }
        return "pid:\(pid)"
    }
}

/// 16×16 pt process icon with fallback to SF Symbol gearshape.
public struct ProcessIconView: View {
    public let pid: Int32
    public let bundleID: String?

    public init(pid: Int32, bundleID: String? = nil) {
        self.pid = pid
        self.bundleID = bundleID
    }

    public var body: some View {
        if let nsImage = ProcessIconCache.shared.icon(for: pid, bundleID: bundleID) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .cornerRadius(3)
        } else {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)
        }
    }
}

/// Section displaying top consuming processes with icons, micro-sparklines, and Activity Monitor affordance.
public struct TopConsumersModule: View {
    public let criterion: ProcessSortCriterion
    public let processes: [ProcessInfoItem]
    public let skippedCount: Int
    public let sparklines: [Int32: [Double]]
    public let standard: Units.ByteUnitStandard

    @Environment(\.motionPolicy) private var motionPolicy

    public init(
        criterion: ProcessSortCriterion,
        processes: [ProcessInfoItem],
        skippedCount: Int = 0,
        sparklines: [Int32: [Double]] = [:],
        standard: Units.ByteUnitStandard = .iec
    ) {
        self.criterion = criterion
        self.processes = processes
        self.skippedCount = skippedCount
        self.sparklines = sparklines
        self.standard = standard
    }

    private var sectionTitle: String {
        skippedCount > 0 ? "Your Apps" : "Top Processes"
    }

    public var body: some View {
        Section(
            sectionTitle,
            trailing: {
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("Activity Monitor")
                            .font(Instrument.Typography.caption)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(CategoryPalette.tint(for: criterion == .cpu ? .cpu : .memory))
                }
                .buttonStyle(.plain)
                .help("Open Activity Monitor")
            }
        ) {
            if processes.isEmpty {
                Text("Analyzing process activity...")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(processes.prefix(5)) { item in
                        HStack(spacing: 8) {
                            ProcessIconView(pid: item.pid, bundleID: item.bundleID)

                            Text(item.name)
                                .font(Instrument.Typography.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            // Micro-sparkline for CPU if history available
                            if criterion == .cpu, let history = sparklines[item.pid], history.count >= 2 {
                                microSparkline(history: history, color: CategoryPalette.color(for: .cpu))
                                    .frame(width: 40, height: 12)
                            }

                            // Value display (tabular SF Pro digits, A13)
                            if criterion == .cpu {
                                Text(String(format: "%.1f%%", item.cpuPercent))
                                    .font(Instrument.Typography.value)
                                    .foregroundColor(.primary)
                            } else {
                                Text(Units.formatBytes(item.memoryBytes, standard: standard))
                                    .font(Instrument.Typography.value)
                                    .foregroundColor(.primary)
                            }
                        }
                        .frame(height: 20)
                        .transition(.opacity)
                    }
                }
                .animation(motionPolicy == .frozen ? nil : Motion.smooth, value: processes.map(\.pid))
            }
        }
    }

    @ViewBuilder
    private func microSparkline(history: [Double], color: Color) -> some View {
        let maxVal = max(1.0, history.max() ?? 100.0)
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width
                let h = proxy.size.height
                let step = history.count > 1 ? w / CGFloat(history.count - 1) : 0

                for (idx, val) in history.enumerated() {
                    let x = CGFloat(idx) * step
                    let y = h - (CGFloat(val / maxVal) * h)
                    if idx == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 1.2)
        }
    }
}

