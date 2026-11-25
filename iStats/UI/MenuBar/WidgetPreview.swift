import AppKit
import SwiftUI
import iStatsCore

/// Rasterizes a `WidgetModel` into a crisp bitmap `NSImage` at 1x or 2x scale,
/// honoring both `MenuBarAppearance` and the requested light/dark `NSAppearance` (Task 9.8).
@MainActor
public enum WidgetPreviewRenderer {
    /// Renders `model` at `scale` (1.0 or 2.0) under the specified `colorScheme` (`.light` -> `.aqua`, `.dark` -> `.darkAqua`).
    ///
    /// Resolves dynamic `NSColor`s (including `.labelColor` for templates and `CategoryPalette` light/dark hexes)
    /// into a concrete `NSBitmapImageRep` so previews display accurately on any surface.
    public static func renderImage(
        model: WidgetModel,
        scale: CGFloat = 2.0,
        colorScheme: ColorScheme
    ) -> NSImage {
        let appearanceName: NSAppearance.Name = (colorScheme == .dark) ? .darkAqua : .aqua
        return renderImage(model: model, scale: scale, appearanceName: appearanceName)
    }

    /// Renders `model` at `scale` (1.0 or 2.0) under the specified `NSAppearance.Name`.
    public static func renderImage(
        model: WidgetModel,
        scale: CGFloat = 2.0,
        appearanceName: NSAppearance.Name
    ) -> NSImage {
        let clampedScale = max(scale, 1.0)
        let appearance = NSAppearance(named: appearanceName) ?? NSAppearance.currentDrawing()

        var rendered: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let vector = WidgetRenderers.draw(model)
            let size = vector.size
            let pixelWidth = max(1, Int((size.width * clampedScale).rounded(.up)))
            let pixelHeight = max(1, Int((size.height * clampedScale).rounded(.up)))

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                rendered = vector
                return
            }
            rep.size = size

            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                ctx.imageInterpolation = .high
                // Draw vector into the bitmap context with template disabled during rasterization
                // so .labelColor resolves against `appearance` (black in light, white in dark).
                let drawCopy = vector.copy() as? NSImage ?? vector
                drawCopy.isTemplate = false
                drawCopy.draw(
                    in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0
                )
            }
            NSGraphicsContext.restoreGraphicsState()

            let output = NSImage(size: size)
            output.addRepresentation(rep)
            output.isTemplate = false
            rendered = output
        }

        return rendered ?? WidgetRenderers.draw(model)
    }

    /// Convenience helper rendering a `WidgetCatalogEntry` with its deterministic sample data.
    public static func renderEntry(
        _ entry: WidgetCatalogEntry,
        appearance: MenuBarAppearance = .statusTint,
        scale: CGFloat = 2.0,
        colorScheme: ColorScheme,
        hasBattery: Bool = true,
        source: MetricSource? = nil,
        throughputLayout: ThroughputLayout? = nil,
        showLabel: Bool = false,
        options baseOptions: WidgetOptions = WidgetOptions()
    ) -> NSImage {
        var opts = baseOptions
        opts.appearance = appearance
        let config = entry.makeConfig(source: source, throughputLayout: throughputLayout, showLabel: showLabel)
        let snapshot = entry.sampleSnapshot(hasBattery: hasBattery)
        let model = WidgetModel.make(config: config, snapshot: snapshot, options: opts)
        return renderImage(model: model, scale: scale, colorScheme: colorScheme)
    }
}

/// SwiftUI view that previews a menu bar `WidgetModel` on a realistic menu bar pill surface,
/// honoring `MenuBarAppearance`, 1x/2x scale, and light/dark appearance (Task 9.8).
public struct WidgetPreview: View {
    public let model: WidgetModel
    public var scale: CGFloat
    public var forcedColorScheme: ColorScheme?
    public var showBackdrop: Bool

    @Environment(\.colorScheme) private var environmentColorScheme

    public init(
        model: WidgetModel,
        scale: CGFloat = 2.0,
        colorScheme: ColorScheme? = nil,
        showBackdrop: Bool = true
    ) {
        self.model = model
        self.scale = scale
        self.forcedColorScheme = colorScheme
        self.showBackdrop = showBackdrop
    }

    /// Initializes a preview from a `WidgetCatalogEntry` using sample data.
    public init(
        entry: WidgetCatalogEntry,
        appearance: MenuBarAppearance = .statusTint,
        hasBattery: Bool = true,
        source: MetricSource? = nil,
        throughputLayout: ThroughputLayout? = nil,
        showLabel: Bool = false,
        options: WidgetOptions = WidgetOptions(),
        scale: CGFloat = 2.0,
        colorScheme: ColorScheme? = nil,
        showBackdrop: Bool = true
    ) {
        var opts = options
        opts.appearance = appearance
        let config = entry.makeConfig(source: source, throughputLayout: throughputLayout, showLabel: showLabel)
        let snapshot = entry.sampleSnapshot(hasBattery: hasBattery)
        self.model = WidgetModel.make(config: config, snapshot: snapshot, options: opts)
        self.scale = scale
        self.forcedColorScheme = colorScheme
        self.showBackdrop = showBackdrop
    }

    /// Initializes a preview from a `MenuBarItemConfig` and live or sample `WidgetSnapshot`.
    public init(
        config: MenuBarItemConfig,
        snapshot: WidgetSnapshot,
        options: WidgetOptions = WidgetOptions(),
        scale: CGFloat = 2.0,
        colorScheme: ColorScheme? = nil,
        showBackdrop: Bool = true
    ) {
        self.model = WidgetModel.make(config: config, snapshot: snapshot, options: options)
        self.scale = scale
        self.forcedColorScheme = colorScheme
        self.showBackdrop = showBackdrop
    }

    private var effectiveScheme: ColorScheme {
        forcedColorScheme ?? environmentColorScheme
    }

    public var body: some View {
        let image = WidgetPreviewRenderer.renderImage(
            model: model,
            scale: scale,
            colorScheme: effectiveScheme
        )

        Group {
            if showBackdrop {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .interpolation(.high)
                    .padding(.horizontal, Instrument.Space.m)
                    .padding(.vertical, Instrument.Space.xs)
                    .frame(minWidth: 54, minHeight: 28)
                    .background(backdropFill)
                    .clipShape(RoundedRectangle(cornerRadius: Instrument.Radius.chip))
                    .overlay(
                        RoundedRectangle(cornerRadius: Instrument.Radius.chip)
                            .strokeBorder(backdropBorder, lineWidth: 0.75)
                    )
            } else {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .interpolation(.high)
            }
        }
        .accessibilityLabel("\(model.category.identity.displayName()) \(model.style.displayName(for: model.category)) preview")
    }

    private var backdropFill: Color {
        effectiveScheme == .dark
            ? Color(white: 0.14)
            : Color(white: 0.94)
    }

    private var backdropBorder: Color {
        effectiveScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
    }
}
