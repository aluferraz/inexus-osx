import AppKit
import CoreGraphics
import NexusCore

/// Per-tick inputs into the renderer.
struct RenderInputs {
    let date: Date
    let cpuLoad: Double          // 0...1
    let memUsage: Double         // 0...1
    let memUsedGB: Double
    let memTotalGB: Double
}

enum LayoutRenderer {

    /// Render a single frame.
    /// - Parameters:
    ///   - background: optional pre-rendered 640×48 RGBA8 frame to use as the
    ///     backdrop. If supplied, the layout draws on top of it and the theme
    ///     background colour is ignored. Use `NexusImage.rasterize` to produce.
    ///   - backgroundDim: 0...100, how much black to mix over the backdrop for
    ///     text readability. Ignored when `background` is nil.
    static func render(layout: Settings.Layout,
                       inputs: RenderInputs,
                       palette: Palette,
                       timeFormat: Settings.TimeFormat,
                       showSeconds: Bool,
                       background: [UInt8]? = nil,
                       backgroundDim: Int = 0) throws -> [UInt8] {
        let canvasRect = CGRect(x: 0, y: 0,
                                width: NexusProtocol.width,
                                height: NexusProtocol.height)

        return try NexusImage.renderToFrame(background: background) { ctx in
            if background == nil {
                ctx.setFillColor(palette.background.cgColor)
                ctx.fill(canvasRect)
            } else if backgroundDim > 0 {
                let alpha = CGFloat(min(100, max(0, backgroundDim))) / 100.0
                ctx.setFillColor(NSColor(red: 0, green: 0, blue: 0, alpha: alpha).cgColor)
                ctx.fill(canvasRect)
            }

            let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            defer { NSGraphicsContext.restoreGraphicsState() }

            switch layout {
            case .clockAndCPU:
                drawClockAndCPU(ctx: ctx, inputs: inputs, palette: palette,
                                timeFormat: timeFormat, showSeconds: showSeconds)
            case .clockCPUMemory:
                drawClockCPUMemory(ctx: ctx, inputs: inputs, palette: palette,
                                   timeFormat: timeFormat, showSeconds: showSeconds)
            case .clockAndDate:
                drawClockAndDate(ctx: ctx, inputs: inputs, palette: palette,
                                 timeFormat: timeFormat, showSeconds: showSeconds)
            case .clockOnly:
                drawClockOnly(ctx: ctx, inputs: inputs, palette: palette,
                              timeFormat: timeFormat, showSeconds: showSeconds)
            case .cpuAndMemory:
                drawCPUAndMemory(ctx: ctx, inputs: inputs, palette: palette)
            }
        }
    }

    // MARK: Time / date formatting

    private static func timeString(_ date: Date, _ format: Settings.TimeFormat, seconds: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch format {
        case .twentyFour: f.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        case .twelveHour: f.dateFormat = seconds ? "h:mm:ss a" : "h:mm a"
        }
        return f.string(from: date)
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date).uppercased()
    }

    // MARK: Layouts

    private static func drawClockAndCPU(ctx: CGContext,
                                        inputs: RenderInputs,
                                        palette: Palette,
                                        timeFormat: Settings.TimeFormat,
                                        showSeconds: Bool) {
        let clock = timeString(inputs.date, timeFormat, seconds: showSeconds)
        drawBigText(clock, at: NSPoint(x: 16, y: 2),
                    size: showSeconds ? 30 : 38, palette: palette)

        drawTinyLabel(dateString(inputs.date),
                      at: NSPoint(x: 18, y: 33),
                      palette: palette)

        drawDivider(ctx: ctx, x: 380, palette: palette)

        drawTinyLabel("CPU", at: NSPoint(x: 400, y: 6), palette: palette)
        drawBigText(String(format: "%3d%%", Int(inputs.cpuLoad * 100)),
                    at: NSPoint(x: 432, y: 0),
                    size: 20, palette: palette, monospaced: true)
        drawBar(ctx: ctx,
                rect: CGRect(x: 400, y: 30, width: 224, height: 10),
                load: inputs.cpuLoad, palette: palette)
    }

    private static func drawClockCPUMemory(ctx: CGContext,
                                           inputs: RenderInputs,
                                           palette: Palette,
                                           timeFormat: Settings.TimeFormat,
                                           showSeconds: Bool) {
        // 3 columns ~ 213px each.
        let clock = timeString(inputs.date, timeFormat, seconds: showSeconds)
        drawBigText(clock, at: NSPoint(x: 12, y: 12),
                    size: 24, palette: palette, monospaced: true)

        drawDivider(ctx: ctx, x: 214, palette: palette)

        // CPU
        drawTinyLabel("CPU", at: NSPoint(x: 230, y: 6), palette: palette)
        drawBigText(String(format: "%3d%%", Int(inputs.cpuLoad * 100)),
                    at: NSPoint(x: 230, y: 14),
                    size: 18, palette: palette, monospaced: true)
        drawBar(ctx: ctx,
                rect: CGRect(x: 230, y: 38, width: 180, height: 6),
                load: inputs.cpuLoad, palette: palette)

        drawDivider(ctx: ctx, x: 420, palette: palette)

        // Memory
        drawTinyLabel("RAM", at: NSPoint(x: 436, y: 6), palette: palette)
        let memLabel = String(format: "%.1f / %.0f GB", inputs.memUsedGB, inputs.memTotalGB)
        drawSmallText(memLabel, at: NSPoint(x: 436, y: 16), palette: palette)
        drawBar(ctx: ctx,
                rect: CGRect(x: 436, y: 38, width: 188, height: 6),
                load: inputs.memUsage, palette: palette)
    }

    private static func drawClockAndDate(ctx: CGContext,
                                         inputs: RenderInputs,
                                         palette: Palette,
                                         timeFormat: Settings.TimeFormat,
                                         showSeconds: Bool) {
        let clock = timeString(inputs.date, timeFormat, seconds: showSeconds)

        // Big date letters (DAY of week + day)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEEE"
        let dayName = f.string(from: inputs.date).uppercased()

        f.dateFormat = "d MMMM yyyy"
        let fullDate = f.string(from: inputs.date)

        drawSmallText(dayName, at: NSPoint(x: 16, y: 4), palette: palette, weight: .semibold, kern: 2.5)
        drawSmallText(fullDate, at: NSPoint(x: 16, y: 28), palette: palette,
                      secondary: true, weight: .regular)

        drawBigText(clock,
                    at: NSPoint(x: NexusProtocol.width - 16, y: 2),
                    size: 32, palette: palette, monospaced: true, rightAligned: true)
    }

    private static func drawClockOnly(ctx: CGContext,
                                      inputs: RenderInputs,
                                      palette: Palette,
                                      timeFormat: Settings.TimeFormat,
                                      showSeconds: Bool) {
        let clock = timeString(inputs.date, timeFormat, seconds: showSeconds)
        drawCenteredBigText(clock, palette: palette, size: 40, monospaced: true)
    }

    private static func drawCPUAndMemory(ctx: CGContext,
                                         inputs: RenderInputs,
                                         palette: Palette) {
        // Two halves: CPU left, RAM right.
        drawTinyLabel("CPU LOAD", at: NSPoint(x: 16, y: 4), palette: palette)
        drawBigText(String(format: "%3d%%", Int(inputs.cpuLoad * 100)),
                    at: NSPoint(x: 16, y: 12), size: 24, palette: palette, monospaced: true)
        drawBar(ctx: ctx,
                rect: CGRect(x: 16, y: 40, width: 280, height: 4),
                load: inputs.cpuLoad, palette: palette)

        drawDivider(ctx: ctx, x: 320, palette: palette)

        drawTinyLabel("MEMORY", at: NSPoint(x: 340, y: 4), palette: palette)
        let pct = inputs.memUsage * 100
        drawBigText(String(format: "%.0f%%", pct),
                    at: NSPoint(x: 340, y: 12), size: 24, palette: palette, monospaced: true)
        let detail = String(format: "%.1f / %.0f GB", inputs.memUsedGB, inputs.memTotalGB)
        drawSmallText(detail, at: NSPoint(x: 440, y: 18), palette: palette, secondary: true)
        drawBar(ctx: ctx,
                rect: CGRect(x: 340, y: 40, width: 284, height: 4),
                load: inputs.memUsage, palette: palette)
    }

    // MARK: Drawing helpers

    private static func drawBigText(_ string: String,
                                    at point: NSPoint,
                                    size: CGFloat,
                                    palette: Palette,
                                    monospaced: Bool = false,
                                    rightAligned: Bool = false) {
        let font: NSFont = monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            : NSFont.systemFont(ofSize: size, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.foreground,
        ]
        let ns = string as NSString
        if rightAligned {
            let w = ns.size(withAttributes: attrs).width
            ns.draw(at: NSPoint(x: point.x - w, y: point.y), withAttributes: attrs)
        } else {
            ns.draw(at: point, withAttributes: attrs)
        }
    }

    private static func drawCenteredBigText(_ string: String,
                                            palette: Palette,
                                            size: CGFloat,
                                            monospaced: Bool = false) {
        let font: NSFont = monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            : NSFont.systemFont(ofSize: size, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.foreground,
        ]
        let ns = string as NSString
        let s = ns.size(withAttributes: attrs)
        let x = (CGFloat(NexusProtocol.width) - s.width) / 2
        let y = (CGFloat(NexusProtocol.height) - s.height) / 2
        ns.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    private static func drawSmallText(_ string: String,
                                      at point: NSPoint,
                                      palette: Palette,
                                      secondary: Bool = false,
                                      weight: NSFont.Weight = .regular,
                                      kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: weight),
            .foregroundColor: secondary ? palette.secondary : palette.foreground,
            .kern: kern,
        ]
        (string as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawTinyLabel(_ string: String,
                                      at point: NSPoint,
                                      palette: Palette) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: palette.secondary,
            .kern: 1.5,
        ]
        (string as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawDivider(ctx: CGContext, x: CGFloat, palette: Palette) {
        ctx.setStrokeColor(palette.divider.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: x, y: 8))
        ctx.addLine(to: CGPoint(x: x, y: 40))
        ctx.strokePath()
    }

    private static func drawBar(ctx: CGContext, rect: CGRect, load: Double, palette: Palette) {
        let radius = rect.height / 2

        // Track.
        ctx.setFillColor(palette.trackEmpty.cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()

        let clamped = max(0, min(1, load))
        guard clamped > 0 else { return }

        let filled = CGRect(x: rect.minX, y: rect.minY,
                            width: rect.width * CGFloat(clamped), height: rect.height)

        // Pick a colour by interpolating through the gradient based on load.
        let color = interpolated(load: clamped, gradient: palette.gradient)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: filled, cornerWidth: radius, cornerHeight: radius, transform: nil))
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
}
