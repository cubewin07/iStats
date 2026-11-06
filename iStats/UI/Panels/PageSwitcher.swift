import SwiftUI
import iStatsCore

/// Glass puck page switcher for Instrument panels (Task 8.6 / ADR 0009).
/// Displays 22×22 icon buttons with a sliding glass puck animated via `matchedGeometryEffect`.
public struct PageSwitcher: View {
    public let pages: [PopoverTab]
    @Binding public var selection: PopoverTab
    public let category: MetricCategory
    @Namespace private var puckNamespace

    public init(
        pages: [PopoverTab],
        selection: Binding<PopoverTab>,
        category: MetricCategory
    ) {
        self.pages = pages
        self._selection = selection
        self.category = category
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(pages) { page in
                let isSelected = (selection == page)
                Button {
                    withAnimation(Motion.snappy) {
                        selection = page
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                                .matchedGeometryEffect(id: "pagePuck", in: puckNamespace)
                        }

                        Image(systemName: iconName(for: page))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(page.title(for: category))
                .accessibilityLabel(page.title(for: category))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func iconName(for page: PopoverTab) -> String {
        switch page {
        case .overview:
            return "circle.lefthalf.filled"
        case .detail:
            switch category {
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .gpu: return "display"
            case .thermal: return "thermometer.medium"
            case .fan: return "fanblades"
            case .network: return "network"
            case .disk: return "internaldrive"
            case .power: return "bolt.battery"
            }
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

