import SwiftUI
import AppKit
import FocusCore

struct Palette {
    let background: Color
    let secondaryBackground: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let warning: Color

    static func island(_ theme: ThemePreference, scheme: ColorScheme, attached: Bool) -> Palette {
        if attached && theme == .system {
            // Hardware-matching chrome, like the physical notch. Menu and Settings
            // still follow macOS appearance; explicit Solarized choices theme every surface.
            return Palette(background: .black, secondaryBackground: .white.opacity(0.10),
                           text: .white, secondaryText: .white.opacity(0.65),
                           accent: .cyan, warning: .orange)
        }
        return resolve(theme, scheme: scheme)
    }

    static func resolve(_ theme: ThemePreference, scheme: ColorScheme) -> Palette {
        switch theme {
        case .solarizedLight:
            return Palette(background: hex(0xfdf6e3), secondaryBackground: hex(0xeee8d5), text: hex(0x586e75), secondaryText: hex(0x657b83), accent: hex(0x268bd2), warning: hex(0xcb4b16))
        case .solarizedDark:
            return Palette(background: hex(0x002b36), secondaryBackground: hex(0x073642), text: hex(0x93a1a1), secondaryText: hex(0x839496), accent: hex(0x2aa198), warning: hex(0xcb4b16))
        case .system:
            return Palette(background: Color(nsColor: .windowBackgroundColor), secondaryBackground: Color(nsColor: .controlBackgroundColor), text: .primary, secondaryText: .secondary, accent: .accentColor, warning: .orange)
        }
    }

    private static func hex(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

extension ThemePreference {
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .solarizedLight: return .light; case .solarizedDark: return .dark }
    }
    var appearance: NSAppearance? {
        switch self { case .system: return nil; case .solarizedLight: return NSAppearance(named: .aqua); case .solarizedDark: return NSAppearance(named: .darkAqua) }
    }
}
