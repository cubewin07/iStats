import SwiftUI
import iStatsCore

/// Compact `info.circle` button opening a popover with a `MetricGlossary` explanation (Task 9.11).
public struct InfoButton: View {
    public let entry: GlossaryEntry

    @State private var isShowingPopover: Bool = false
    @State private var isHovered: Bool = false

    public init(term: MetricTerm) {
        self.entry = MetricGlossary.entry(for: term)
    }

    public init(key term: MetricTerm) {
        self.entry = MetricGlossary.entry(for: term)
    }

    public init?(key: String) {
        guard let resolved = MetricGlossary.entry(forKey: key) else { return nil }
        self.entry = resolved
    }

    public init(entry: GlossaryEntry) {
        self.entry = entry
    }

    public var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(Instrument.Typography.icon(Instrument.Icon.small, weight: .regular))
                .foregroundStyle(isHovered || isShowingPopover ? .primary : .secondary)
                .frame(width: 15, height: 15)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            isHovered = hovering
        }
        .help("About \(entry.title)")
        .accessibilityLabel("About \(entry.title)")
        .accessibilityHint("Explains \(entry.title) and typical values")
        .popover(isPresented: $isShowingPopover, arrowEdge: .trailing) {
            GlossaryPopoverContent(entry: entry)
        }
    }
}

private struct GlossaryPopoverContent: View {
    let entry: GlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.m) {
            Text(entry.title)
                .font(Instrument.Typography.headlineStrong)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.summary)
                .font(Instrument.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Instrument.Space.xxs) {
                Text("WHAT'S TYPICAL")
                    .font(Instrument.Typography.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)

                Text(entry.typical)
                    .font(Instrument.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Instrument.Space.l)
        .frame(width: 264, alignment: .leading)
    }
}

/// Glossary sheet opened via `?` in `MetricPanel` or the `⋯` menu (Task 9.11).
public struct GlossarySheetView: View {
    public let destination: PanelDestination
    public let enabledCategories: Set<MetricCategory>
    public let hasBattery: Bool
    public let onDismiss: () -> Void

    public init(
        destination: PanelDestination,
        enabledCategories: Set<MetricCategory> = Set(MetricCategory.allCases),
        hasBattery: Bool = true,
        onDismiss: @escaping () -> Void
    ) {
        self.destination = destination
        self.enabledCategories = enabledCategories
        self.hasBattery = hasBattery
        self.onDismiss = onDismiss
    }

    private var entries: [GlossaryEntry] {
        MetricGlossary.entries(for: destination, enabledCategories: enabledCategories)
    }

    private var headerTitle: String {
        switch destination {
        case .overview:
            return "Metric Glossary"
        case .category(let category):
            return "\(category.identity.displayName(hasBattery: hasBattery)) Glossary"
        }
    }

    private var headerSymbol: String {
        switch destination {
        case .overview:
            return "book"
        case .category(let category):
            return category.identity.symbol(hasBattery: hasBattery)
        }
    }

    private var accentColor: Color {
        switch destination {
        case .overview:
            return .accentColor
        case .category(let category):
            return CategoryPalette.tint(for: category)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Instrument.Space.s) {
                Image(systemName: headerSymbol)
                    .font(Instrument.Typography.icon(Instrument.Icon.medium, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text(headerTitle)
                    .font(Instrument.Typography.title)
                    .foregroundStyle(.primary)

                Spacer()

                Button("Done", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
            .padding(.horizontal, Instrument.Space.xl)
            .padding(.vertical, Instrument.Space.l)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Instrument.Space.m) {
                    if destination == .overview {
                        let grouped = Dictionary(grouping: entries, by: \.category)
                        let ordered = MetricCategory.allCases.filter { grouped[$0]?.isEmpty == false }
                        ForEach(ordered, id: \.self) { category in
                            VStack(alignment: .leading, spacing: Instrument.Space.s) {
                                Text(category.identity.displayName(hasBattery: hasBattery).uppercased())
                                    .font(Instrument.Typography.eyebrow)
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)

                                ForEach(grouped[category] ?? []) { entry in
                                    glossaryCard(entry)
                                }
                            }
                        }
                    } else {
                        ForEach(entries) { entry in
                            glossaryCard(entry)
                        }
                    }
                }
                .padding(Instrument.Space.xl)
            }
        }
        .frame(width: 336, height: 380)
        .background(Instrument.Surface.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerTitle)
    }

    private func glossaryCard(_ entry: GlossaryEntry) -> some View {
        VStack(alignment: .leading, spacing: Instrument.Space.xs) {
            Text(entry.title)
                .font(Instrument.Typography.headlineStrong)
                .foregroundStyle(.primary)

            Text(entry.summary)
                .font(Instrument.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Typical: \(entry.typical)")
                .font(Instrument.Typography.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Instrument.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                .fill(Instrument.Surface.module)
        )
    }
}
