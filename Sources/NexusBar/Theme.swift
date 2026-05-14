import AppKit

/// Color palette for the rendered Nexus frame.
struct Palette {
    let background: NSColor
    let foreground: NSColor
    let secondary: NSColor
    let divider: NSColor
    let trackEmpty: NSColor
    let accent: NSColor          // single-colour version of bar (used when no gradient)
    let gradient: [NSColor]      // 2+ colors, used along the load axis (left → right)
}

extension Settings.Theme {
    var palette: Palette {
        switch self {
        case .dark:
            return Palette(
                background: NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1),
                foreground: .white,
                secondary: NSColor(white: 0.55, alpha: 1),
                divider:   NSColor(white: 0.18, alpha: 1),
                trackEmpty: NSColor(white: 0.10, alpha: 1),
                accent: NSColor(red: 0.30, green: 0.78, blue: 0.50, alpha: 1),
                gradient: [
                    NSColor(red: 0.30, green: 0.78, blue: 0.50, alpha: 1),
                    NSColor(red: 0.95, green: 0.74, blue: 0.20, alpha: 1),
                    NSColor(red: 0.93, green: 0.30, blue: 0.30, alpha: 1),
                ]
            )
        case .midnight:
            return Palette(
                background: NSColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 1),
                foreground: NSColor(red: 0.78, green: 0.89, blue: 1.00, alpha: 1),
                secondary: NSColor(red: 0.40, green: 0.55, blue: 0.78, alpha: 1),
                divider:   NSColor(red: 0.10, green: 0.18, blue: 0.32, alpha: 1),
                trackEmpty: NSColor(red: 0.07, green: 0.12, blue: 0.22, alpha: 1),
                accent: NSColor(red: 0.35, green: 0.70, blue: 1.00, alpha: 1),
                gradient: [
                    NSColor(red: 0.30, green: 0.55, blue: 1.00, alpha: 1),
                    NSColor(red: 0.55, green: 0.42, blue: 1.00, alpha: 1),
                    NSColor(red: 0.85, green: 0.35, blue: 1.00, alpha: 1),
                ]
            )
        case .sunset:
            return Palette(
                background: NSColor(red: 0.10, green: 0.04, blue: 0.08, alpha: 1),
                foreground: NSColor(red: 1.00, green: 0.92, blue: 0.82, alpha: 1),
                secondary: NSColor(red: 0.78, green: 0.55, blue: 0.45, alpha: 1),
                divider:   NSColor(red: 0.28, green: 0.14, blue: 0.10, alpha: 1),
                trackEmpty: NSColor(red: 0.18, green: 0.08, blue: 0.08, alpha: 1),
                accent: NSColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1),
                gradient: [
                    NSColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
                    NSColor(red: 1.00, green: 0.45, blue: 0.20, alpha: 1),
                    NSColor(red: 0.92, green: 0.18, blue: 0.40, alpha: 1),
                ]
            )
        case .mono:
            return Palette(
                background: .black,
                foreground: .white,
                secondary: NSColor(white: 0.60, alpha: 1),
                divider:   NSColor(white: 0.25, alpha: 1),
                trackEmpty: NSColor(white: 0.15, alpha: 1),
                accent: .white,
                gradient: [.white, .white]
            )
        case .ocean:
            return Palette(
                background: NSColor(red: 0.02, green: 0.10, blue: 0.12, alpha: 1),
                foreground: NSColor(red: 0.85, green: 0.98, blue: 1.00, alpha: 1),
                secondary: NSColor(red: 0.45, green: 0.75, blue: 0.78, alpha: 1),
                divider:   NSColor(red: 0.08, green: 0.22, blue: 0.26, alpha: 1),
                trackEmpty: NSColor(red: 0.05, green: 0.14, blue: 0.18, alpha: 1),
                accent: NSColor(red: 0.20, green: 0.85, blue: 0.92, alpha: 1),
                gradient: [
                    NSColor(red: 0.10, green: 0.92, blue: 0.78, alpha: 1),
                    NSColor(red: 0.20, green: 0.65, blue: 0.95, alpha: 1),
                    NSColor(red: 0.40, green: 0.35, blue: 0.92, alpha: 1),
                ]
            )
        }
    }
}
