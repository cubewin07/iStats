import Foundation

/// Where a popover panel is pointed: the cross-category Overview or one category page.
public enum PanelDestination: Hashable, Sendable, Codable {
    case overview
    case category(MetricCategory)

    /// `"overview"` or the category raw value. Pinned origins saved before destinations
    /// existed were keyed by category raw value, so they stay valid.
    public var storageKey: String {
        switch self {
        case .overview: return "overview"
        case .category(let category): return category.rawValue
        }
    }

    public init?(storageKey: String) {
        if storageKey == "overview" {
            self = .overview
        } else if let category = MetricCategory(rawValue: storageKey) {
            self = .category(category)
        } else {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let destination = PanelDestination(storageKey: key) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown panel destination '\(key)'"
            ))
        }
        self = destination
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }

    public var category: MetricCategory? {
        if case .category(let category) = self { return category }
        return nil
    }

    /// Enabled categories in `MetricCategory.allCases` order (the strip order).
    public static func orderedCategories(enabled: Set<MetricCategory>) -> [MetricCategory] {
        MetricCategory.allCases.filter { enabled.contains($0) }
    }

    /// Strip destinations: Overview first, then each enabled category in `allCases` order.
    public static func strip(enabled: Set<MetricCategory>) -> [PanelDestination] {
        strip(categories: orderedCategories(enabled: enabled))
    }

    public static func strip(categories: [MetricCategory]) -> [PanelDestination] {
        [.overview] + categories.map { PanelDestination.category($0) }
    }

    /// The destination `offset` steps away, cycling Overview, then `categories` in the given order,
    /// wrapping at both ends. A category that is not in `categories` (for example one just disabled)
    /// is treated as sitting at Overview, so stepping still lands on a valid strip entry.
    public func neighbor(offset: Int, in categories: [MetricCategory]) -> PanelDestination {
        let sequence = Self.strip(categories: categories)
        let index = sequence.firstIndex(of: self) ?? 0
        let count = sequence.count
        let wrapped = ((index + offset) % count + count) % count
        return sequence[wrapped]
    }
}

/// How menu bar widgets are tinted.
public enum MenuBarAppearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case monochrome
    case statusTint
    case categoryColor

    public var id: String { rawValue }
}
