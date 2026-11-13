import Foundation
import CoreGraphics

/// Pure geometry helper for positioning floating borderless panels relative to menu bar status items.
public enum PanelPlacement {

    /// Calculates the optimal frame for a panel relative to a status item button.
    /// - Parameters:
    ///   - buttonRect: The status item's screen-coordinate bounding box.
    ///   - panelSize: The required size of the panel.
    ///   - visibleFrame: The visible screen area (excluding menu bar and Dock) in screen coordinates.
    ///   - gap: Vertical separation between button and panel (default 6 pt).
    ///   - margin: Minimum margin from screen edges (default 8 pt).
    /// - Returns: Positioned panel frame in screen coordinates.
    public static func frame(
        for buttonRect: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 6.0,
        margin: CGFloat = 8.0
    ) -> CGRect {
        // 1. Horizontal positioning: center on the status button
        var x = buttonRect.midX - (panelSize.width / 2.0)

        // Clamp to screen bounds with margin
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - margin - panelSize.width

        if minX <= maxX {
            x = min(max(x, minX), maxX)
        } else {
            // Screen narrower than panel + margins
            x = minX
        }

        // 2. Vertical positioning: default below status item
        var y = buttonRect.minY - gap - panelSize.height

        // If there isn't room below the item, place it above (e.g. bottom bar)
        if y < visibleFrame.minY + margin {
            let yAbove = buttonRect.maxY + gap
            if yAbove + panelSize.height <= visibleFrame.maxY + 32.0 { // Allow overlap with menu bar if flipped
                y = yAbove
            } else {
                // Pin to bottom visible margin
                y = visibleFrame.minY + margin
            }
        }

        // Final vertical safety clamp
        if y + panelSize.height > visibleFrame.maxY + gap + 30.0 {
            y = visibleFrame.maxY - panelSize.height
        }

        return CGRect(
            x: round(x),
            y: round(y),
            width: round(panelSize.width),
            height: round(panelSize.height)
        )
    }
}
