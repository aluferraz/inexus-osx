import AppKit
import CoreGraphics
import NexusCore

/// Renders a single live-data widget into an arbitrary rect on the 640×48 canvas.
/// Used by free-layout pages.
enum WidgetRenderer {

    static func draw(_ kind: WidgetKind,
                     in rect: CGRect,
                     inputs: RenderInputs,
                     palette: Palette,
                     timeFormat: Settings.TimeFormat,
                     showSeconds: Bool) {
        switch kind {
        case .clock:
            drawFittedText(timeString(inputs.date, timeFormat, seconds: showSeconds),
                           in: rect, palette: palette, monospaced: true)
        case .clockHHMM:
            drawFittedText(timeString(inputs.date, timeFormat, seconds: false),
                           in: rect, palette: palette, monospaced: true)
        case .dateLong:
            drawFittedText(longDate(inputs.date), in: rect, palette: palette)
        case .dateShort:
            drawFittedText(shortDate(inputs.date), in: rect, palette: palette, kern: 1.5)
        case .cpuPercent:
            drawFittedText(String(format: "%d%%", Int(inputs.cpuLoad * 100)),
                           in: rect, palette: palette, monospaced: true)
        case .cpuBar:
            drawBar(rect: rect, load: inputs.cpuLoad, palette: palette)
        case .ramPercent:
            drawFittedText(String(format: "%d%%", Int(inputs.memUsage * 100)),
                           in: rect, palette: palette, monospaced: true)
        case .ramBar:
            drawBar(rect: rect, load: inputs.memUsage, palette: palette)
        case .ramUsage:
            let s = String(format: "%.1f / %.0f GB", inputs.memUsedGB, inputs.memTotalGB)
            drawFittedText(s, in: rect, palette: palette)
        }
    }

    // MARK: Drawing helpers

    /// Find the largest font size that fits `text` inside `rect`, then draw centred.
    private static func drawFittedText(_ text: String,
                                       in rect: CGRect,
                                       palette: Palette,
                                       monospaced: Bool = false,
                                       kern: CGFloat = 0) {
        guard !text.isEmpty, rect.width > 1, rect.height > 1 else { return }
        let weight: NSFont.Weight = .medium
        var fontSize = max(6, rect.height)
        var attrs: [NSAttributedString.Key: Any] = [:]
        var measured: CGSize = .zero

        while fontSize >= 6 {
            let font = monospaced
                ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
                : NSFont.systemFont(ofSize: fontSize, weight: weight)
            attrs = [
                .font: font,
                .foregroundColor: palette.foreground,
                .kern: kern,
            ]
            measured = (text as NSString).size(withAttributes: attrs)
            if measured.width <= rect.width && measured.height <= rect.height { break }
            fontSize -= 1
        }

        let x = rect.midX - measured.width / 2
        let y = rect.midY - measured.height / 2
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    private static func drawBar(rect: CGRect, load: Double, palette: Palette) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let radius = min(rect.height, rect.width) / 2

        ctx.setFillColor(palette.trackEmpty.cgColor)
        ctx.addPath(CGPath(roundedRect: rect,
                           cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.fillPath()

        let clamped = max(0, min(1, load))
        guard clamped > 0 else { return }
        let filled = CGRect(x: rect.minX, y: rect.minY,
                            width: rect.width * CGFloat(clamped),
                            height: rect.height)
        let color = interpolated(load: clamped, gradient: palette.gradient)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: filled,
                           cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.fillPath()
    }

    private static func interpolated(load: Double, gradient: [NSColor]) -> NSColor {
        guard gradient.count > 1 else { return gradient.first ?? .white }
        let scaled = load * Double(gradient.count - 1)
        let lower = Int(scaled.rounded(.down))
        let upper = min(gradient.count - 1, lower + 1)
        let t = CGFloat(scaled - Double(lower))
        let a = gradient[lower].usingColorSpace(.sRGB) ?? gradient[lower]
        let b = gradient[upper].usingColorSpace(.sRGB) ?? gradient[upper]
        return NSColor(red: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: 1)
    }

    // MARK: Time / date formatting

    private static func timeString(_ date: Date,
                                   _ format: Settings.TimeFormat,
                                   seconds: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch format {
        case .twentyFour: f.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        case .twelveHour: f.dateFormat = seconds ? "h:mm:ss a" : "h:mm a"
        }
        return f.string(from: date)
    }

    private static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date).uppercased()
    }
}
