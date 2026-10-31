import SwiftUI
import iStatsCore

/// Standard segmented tab bar used within category popovers, supporting ⌘1–⌘3 navigation.
public struct TabBar: View {
    public let category: MetricCategory
    public let tabs: [PopoverTab]
    @Binding public var selectedTab: PopoverTab
    public var hasDetailedGPUEngines: Bool

    public init(
        category: MetricCategory,
        tabs: [PopoverTab],
        selectedTab: Binding<PopoverTab>,
        hasDetailedGPUEngines: Bool = true
    ) {
        self.category = category
        self.tabs = tabs
        self._selectedTab = selectedTab
        self.hasDetailedGPUEngines = hasDetailedGPUEngines
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title(for: category, hasDetailedGPUEngines: hasDetailedGPUEngines))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color(nsColor: .controlAccentColor).opacity(0.18) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSelected ? Color(nsColor: .controlAccentColor).opacity(0.35) : Color.clear, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityLabel("\(tab.title(for: category, hasDetailedGPUEngines: hasDetailedGPUEngines)) Tab (⌘\(index + 1))")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.10))
        )
    }
}

#Preview("TabBar - 3 Tabs") {
    struct TabBarPreviewWrapper: View {
        @State private var currentTab: PopoverTab = .overview
        var body: some View {
            TabBar(
                category: .cpu,
                tabs: [.overview, .detail, .history],
                selectedTab: $currentTab
            )
            .padding()
            .frame(width: Tokens.popoverWidth)
        }
    }
    return TabBarPreviewWrapper()
}
