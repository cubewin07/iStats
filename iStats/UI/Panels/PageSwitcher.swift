import SwiftUI
import iStatsCore

/// Glass puck text page switcher for Instrument panels (Task 8.5.6b / ADR 0010).
/// Displays `Now · Details · History` using Kit v2 `SegmentedControl` with a sliding glass puck.
public struct PageSwitcher: View {
    public let pages: [PopoverTab]
    @Binding public var selection: PopoverTab
    public let category: MetricCategory

    public init(
        pages: [PopoverTab],
        selection: Binding<PopoverTab>,
        category: MetricCategory
    ) {
        self.pages = pages
        self._selection = selection
        self.category = category
    }

    public static func label(for page: PopoverTab) -> String {
        switch page {
        case .overview:
            return "Now"
        case .detail:
            return "Details"
        case .history:
            return "History"
        }
    }

    public static func accessibilityLabel(for page: PopoverTab, category: MetricCategory) -> String {
        let short = label(for: page)
        let contextual = page.title(for: category)
        return contextual == short ? short : "\(short), \(contextual)"
    }

    public var body: some View {
        SegmentedControl(
            options: pages,
            selection: $selection,
            fontSize: 11,
            horizontalPadding: 6,
            verticalPadding: 3,
            accessibilityLabel: { page in
                Self.accessibilityLabel(for: page, category: category)
            }
        ) { page in
            Self.label(for: page)
        }
        .fixedSize(horizontal: true, vertical: false)
        .help("Switch page (⌘1–3)")
        .accessibilityHint("Use Command 1 to 3 to switch pages")
    }
}

