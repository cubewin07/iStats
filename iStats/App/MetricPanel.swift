import AppKit
import SwiftUI
import iStatsCore

/// Keyboard commands dispatched from MetricPanel to UI observers (Task 9.3 / ADR 0011).
public enum PanelCommand: Sendable, Equatable {
    case previousPage
    case nextPage
    /// 0-based strip index (0 = Overview, 1... = enabled categories).
    case selectDestination(Int)
    case nextDestination
    case previousDestination
    case togglePin
    case openPreferences
    case quit
    /// Stub hook for Task 9.11 glossary sheet (`?`).
    case showGlossary
    case close
}

extension Notification.Name {
    public static let panelCommandReceived = Notification.Name("iStats.panelCommandReceived")
}

/// A custom borderless glass panel hosting SwiftUI instrument views (ADR 0009 / Task 8.3, ADR 0011 / Task 9.3).
public final class MetricPanel: NSPanel {

    public var destination: PanelDestination?

    /// Computed shim over `destination` for existing category-oriented callers.
    public var category: MetricCategory? {
        get { destination?.category }
        set { destination = newValue.map { .category($0) } }
    }

    public var isPinned: Bool = false {
        didSet {
            updatePinState()
        }
    }

    public var onCloseRequested: (() -> Void)?
    public var onUnpinRequested: (() -> Void)?
    public var onGlossaryRequested: (() -> Void)?
    public var onCommand: ((PanelCommand) -> Void)?
    public var onContentHeightChanged: ((CGFloat) -> Void)?

    /// Persistent glass backdrop + SwiftUI host (reused across category switches; A11 / 8.5.6a).
    internal let backgroundContainer = PanelBackgroundView()
    internal let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    internal var targetHeight: CGFloat?

    public init(contentRect: NSRect = NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 400)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false

        // Disable NSHostingView auto-sizing constraints so Auto Layout never fights animated setFrame.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true

        backgroundContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: backgroundContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: backgroundContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundContainer.bottomAnchor)
        ])

        self.contentView = backgroundContainer
    }

    public override var canBecomeKey: Bool {
        true
    }

    public override var canBecomeMain: Bool {
        false
    }

    private func updatePinState() {
        if isPinned {
            level = .floating
            isMovableByWindowBackground = true
        } else {
            level = .statusBar
            isMovableByWindowBackground = false
        }
    }

    private func postCommand(_ command: PanelCommand) {
        var info: [AnyHashable: Any] = [:]
        if let destination {
            info["destination"] = destination
            if let category = destination.category {
                info["category"] = category
            }
        }
        NotificationCenter.default.post(
            name: .panelCommandReceived,
            object: command,
            userInfo: info.isEmpty ? nil : info
        )
        onCommand?(command)
    }

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        let input = PanelKeyInput(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? "",
            command: flags.contains(.command),
            control: flags.contains(.control),
            shift: flags.contains(.shift),
            option: flags.contains(.option)
        )

        guard let action = PanelKeyMap.action(for: input, isPinned: isPinned) else {
            super.keyDown(with: event)
            return
        }

        switch action {
        case .noOp:
            return
        case .close:
            onCloseRequested?()
            postCommand(.close)
        case .unpin:
            onUnpinRequested?()
        case .copy:
            if !CopyHoverCoordinator.shared.copyActiveText() {
                super.keyDown(with: event)
            }
        case .selectDestination(let index):
            postCommand(.selectDestination(index))
        case .nextDestination:
            postCommand(.nextDestination)
        case .previousDestination:
            postCommand(.previousDestination)
        case .previousPage:
            postCommand(.previousPage)
        case .nextPage:
            postCommand(.nextPage)
        case .togglePin:
            postCommand(.togglePin)
        case .openSettings:
            postCommand(.openPreferences)
        case .quit:
            postCommand(.quit)
        case .showGlossary:
            onGlossaryRequested?()
            postCommand(.showGlossary)
        }
    }

    /// Swaps the SwiftUI root view in place on the persistent hosting view without rebuilding AppKit layers.
    public func setSwiftUIContent<V: View>(_ view: V) {
        let wrapped = view
            .onPreferenceChange(PanelContentHeightKey.self) { [weak self] height in
                guard let self, height > 0 else { return }
                self.onContentHeightChanged?(height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        hostingView.rootView = AnyView(wrapped)
    }

    /// Tears down hosted SwiftUI content so timelines stop and `onDisappear` fires cleanly.
    public func clearContent() {
        hostingView.layer?.removeAnimation(forKey: "openTransform")
        hostingView.rootView = AnyView(EmptyView())
        targetHeight = nil
    }

    /// Runs the content-layer open transform animation (scale 0.96 -> 1.0 top-anchored, y -6 -> 0).
    public func animateOpenTransform() {
        guard NSClassFromString("XCTestCase") == nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = hostingView.layer else {
            return
        }
        layer.removeAnimation(forKey: "openTransform")

        let bounds = hostingView.bounds
        let cx = bounds.width / 2.0
        let topY = hostingView.isFlipped ? 0.0 : bounds.height
        let yShift: CGFloat = hostingView.isFlipped ? -6.0 : 6.0

        var start = CATransform3DIdentity
        start = CATransform3DTranslate(start, cx, topY, 0)
        start = CATransform3DScale(start, 0.96, 0.96, 1.0)
        start = CATransform3DTranslate(start, -cx, -topY, 0)
        start = CATransform3DTranslate(start, 0, yShift, 0)

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = start
        anim.toValue = CATransform3DIdentity
        anim.duration = 0.28
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
        layer.transform = CATransform3DIdentity
        layer.add(anim, forKey: "openTransform")
    }
}

// MARK: - Panel Background View (Liquid Glass on macOS 26+ / NSVisualEffectView fallback)

final class PanelBackgroundView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBackground()
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        super.updateLayer()
        updateBorderAppearance()
    }

    private func updateBorderAppearance() {
        let match = effectiveAppearance.bestMatch(from: [
            .accessibilityHighContrastDarkAqua,
            .darkAqua,
            .accessibilityHighContrastAqua,
            .aqua
        ])
        let isDark = (match == .darkAqua || match == .accessibilityHighContrastDarkAqua)
        let isHighContrast = (match == .accessibilityHighContrastDarkAqua || match == .accessibilityHighContrastAqua)

        if isDark {
            layer?.borderColor = NSColor.white.withAlphaComponent(isHighContrast ? 0.35 : 0.18).cgColor
        } else {
            layer?.borderColor = NSColor.black.withAlphaComponent(isHighContrast ? 0.28 : 0.12).cgColor
        }
    }

    private func setupBackground() {
        wantsLayer = true
        layer?.cornerRadius = Instrument.Radius.panel
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        updateBorderAppearance()

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = Instrument.Radius.panel
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.wantsLayer = true
            glassView.layer?.cornerRadius = Instrument.Radius.panel
            glassView.layer?.cornerCurve = .continuous
            glassView.layer?.masksToBounds = true
            addSubview(glassView, positioned: .below, relativeTo: nil)

            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassView.topAnchor.constraint(equalTo: topAnchor),
                glassView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .popover
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = Instrument.Radius.panel
            visualEffect.layer?.cornerCurve = .continuous
            visualEffect.layer?.masksToBounds = true
            visualEffect.translatesAutoresizingMaskIntoConstraints = false
            addSubview(visualEffect, positioned: .below, relativeTo: nil)

            NSLayoutConstraint.activate([
                visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
                visualEffect.topAnchor.constraint(equalTo: topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
