import SwiftUI
import CoreGraphics

extension EnvironmentValues {
    internal var panelScaffoldProbeEnabled: Bool {
        get { self[PanelScaffoldProbeEnabledKey.self] }
        set { self[PanelScaffoldProbeEnabledKey.self] = newValue }
    }
}

private struct PanelScaffoldProbeEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

internal struct PanelScaffoldProbeSnapshot: Equatable, Sendable {
    var glanceSummary: String?
    var glanceFrame: CGRect?
    var chartFrame: CGRect?
    var insightText: String?
    var insightFrame: CGRect?
    var badgeTitle: String?
    var eyebrowFrame: CGRect?
    var headerStripFrame: CGRect?
    var headerStripButtonCount: Int?
    var titleRowFrame: CGRect?
    var footerFrame: CGRect?
    var footerStatusText: String?
    var inlineStatusText: String?
    var inlineStatusFrame: CGRect?
    var hasActionRibbon: Bool?
    var ribbonActionTitle: String?
}

internal struct PanelScaffoldProbeKey: PreferenceKey {
    static let defaultValue = PanelScaffoldProbeSnapshot()

    static func reduce(value: inout PanelScaffoldProbeSnapshot, nextValue: () -> PanelScaffoldProbeSnapshot) {
        let next = nextValue()
        if let s = next.glanceSummary { value.glanceSummary = s }
        if let f = next.glanceFrame { value.glanceFrame = f }
        if let f = next.chartFrame { value.chartFrame = f }
        if let t = next.insightText { value.insightText = t }
        if let f = next.insightFrame { value.insightFrame = f }
        if let b = next.badgeTitle { value.badgeTitle = b }
        if let f = next.eyebrowFrame { value.eyebrowFrame = f }
        if let f = next.headerStripFrame { value.headerStripFrame = f }
        if let c = next.headerStripButtonCount { value.headerStripButtonCount = c }
        if let f = next.titleRowFrame { value.titleRowFrame = f }
        if let f = next.footerFrame { value.footerFrame = f }
        if let s = next.footerStatusText { value.footerStatusText = s }
        if let s = next.inlineStatusText { value.inlineStatusText = s }
        if let f = next.inlineStatusFrame { value.inlineStatusFrame = f }
        if let r = next.hasActionRibbon { value.hasActionRibbon = r }
        if let t = next.ribbonActionTitle { value.ribbonActionTitle = t }
    }
}
