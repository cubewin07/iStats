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
}

/// How menu bar widgets are tinted.
public enum MenuBarAppearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case monochrome
    case statusTint
    case categoryColor

    public var id: String { rawValue }
}
