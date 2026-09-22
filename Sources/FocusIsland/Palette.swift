import SwiftUI
import AppKit

struct Palette {
    let background: Color
    let secondaryBackground: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let warning: Color

    static func island(attached: Bool) -> Palette {
        if attached {
            // Keep the attached shell black so it blends with the physical notch.
            return Palette(background: .black, secondaryBackground: .white.opacity(0.10),
                           text: .white, secondaryText: .white.opacity(0.65),
                           accent: .cyan, warning: .orange)
        }
        return system
    }

    static var system: Palette {
        Palette(background: Color(nsColor: .windowBackgroundColor),
                secondaryBackground: Color(nsColor: .controlBackgroundColor),
                text: .primary, secondaryText: .secondary,
                accent: .accentColor, warning: .orange)
    }
}
