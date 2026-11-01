import AppKit
import SwiftUI
import iStatsCore

/// A custom borderless glass panel hosting SwiftUI instrument views (ADR 0009 / Task 8.3).
public final class MetricPanel: NSPanel {

    public var isPinned: Bool = false {
        didSet {
            updatePinState()
        }
    }

    public var onCloseRequested: (() -> Void)?
    public var onUnpinRequested: (() -> Void)?

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

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if isPinned {
                onUnpinRequested?()
            } else {
                onCloseRequested?()
            }
            return
        }
        super.keyDown(with: event)
    }

    public func setSwiftUIContent<V: View>(_ view: V) {
        let backgroundContainer = PanelBackgroundView()
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        backgroundContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: backgroundContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: backgroundContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundContainer.bottomAnchor)
        ])

        self.contentView = backgroundContainer
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

    private func setupBackground() {
        wantsLayer = true
        layer?.cornerRadius = Instrument.Radius.panel
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = Instrument.Radius.panel
            glassView.translatesAutoresizingMaskIntoConstraints = false
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
