import AppKit
import CoreGraphics
import NexusCore

/// Renders button-grid pages and the page-indicator dots into a 640×48 frame.
enum PageRenderer {

    /// Render a button-grid page. `pressedIndex` highlights one button briefly
    /// (called from a touch handler) and is otherwise nil.
    static func renderButtonGrid(page: Page,
                                 palette: Palette,
                                 background: [UInt8]?,
                                 backgroundDim: Int,
                                 pressedIndex: Int?,
                                 pageIndex: Int,
                                 pageCount: Int) throws -> [UInt8] {
        let canvas = CGRect(x: 0, y: 0,
                            width: NexusProtocol.width,
                            height: NexusProtocol.height)

        return try NexusImage.renderToFrame(background: background) { ctx in
            if background == nil {
                ctx.setFillColor(palette.background.cgColor)
                ctx.fill(canvas)
            } else if backgroundDim > 0 {
                let a = CGFloat(min(100, max(0, backgroundDim))) / 100
                ctx.setFillColor(NSColor(red: 0, green: 0, blue: 0, alpha: a).cgColor)
                ctx.fill(canvas)
            }

            let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            defer { NSGraphicsContext.restoreGraphicsState() }

            if page.buttons.isEmpty {
                drawCentredText("(empty page — add buttons in the editor)",
                                palette: palette, size: 14)
            } else {
                drawButtons(page.buttons, palette: palette, pressedIndex: pressedIndex)
            }

            drawPageDots(currentIndex: pageIndex,
                         total: pageCount,
                         palette: palette,
                         in: ctx)
        }
    }

    /// Overlay just the page dots onto an already-rendered status frame.
    /// Used so all page kinds get the same swipe affordance.
    static func overlayPageDots(on frame: [UInt8],
                                palette: Palette,
                                pageIndex: Int,
                                pageCount: Int) throws -> [UInt8] {
        guard pageCount > 1 else { return frame }
        return try NexusImage.renderToFrame(background: frame) { ctx in
            drawPageDots(currentIndex: pageIndex,
                         total: pageCount,
                         palette: palette,
                         in: ctx)
        }
    }

    // MARK: Buttons

    private static func drawButtons(_ buttons: [PageButton],
                                    palette: Palette,
                                    pressedIndex: Int?) {
        let n = buttons.count
        let cellW = CGFloat(NexusProtocol.width) / CGFloat(n)
        for (i, btn) in buttons.enumerated() {
            let cell = CGRect(x: CGFloat(i) * cellW, y: 0,
                              width: cellW, height: CGFloat(NexusProtocol.height))
            drawButton(btn, in: cell, palette: palette, pressed: pressedIndex == i)
        }
    }

    private static func drawButton(_ button: PageButton,
                                   in cell: CGRect,
                                   palette: Palette,
                                   pressed: Bool) {
        if pressed {
            let bg = palette.accent.withAlphaComponent(0.30)
            bg.setFill()
            let r = cell.insetBy(dx: 2, dy: 2)
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        }

        // Layout: icon on top, label centred underneath. If label is empty,
        // centre the icon vertically. Stay clear of the page-dot strip up top.
        let hasLabel = !button.label.isEmpty
        let labelHeight: CGFloat = hasLabel ? 12 : 0
        let topPadding: CGFloat = 5
        let iconArea = CGRect(x: cell.minX + 4,
                              y: cell.minY + topPadding,
                              width: cell.width - 8,
                              height: cell.height - topPadding - labelHeight - 2)

        let iconSize = min(iconArea.height, hasLabel ? 24 : 30)
        let iconRect = CGRect(x: iconArea.midX - iconSize / 2,
                              y: iconArea.midY - iconSize / 2,
                              width: iconSize, height: iconSize)
        drawIcon(button.icon, in: iconRect, palette: palette)

        if hasLabel {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: palette.foreground,
            ]
            let ns = button.label as NSString
            let trimmed = truncate(button.label, toWidth: cell.width - 6, attrs: attrs)
            let s = (trimmed as NSString).size(withAttributes: attrs)
            (trimmed as NSString).draw(at: NSPoint(x: cell.midX - s.width / 2,
                                                   y: cell.maxY - s.height - 2),
                                       withAttributes: attrs)
            _ = ns // silence unused
        }
    }

    private static func drawIcon(_ icon: ButtonIcon, in rect: CGRect, palette: Palette) {
        switch icon {
        case .sfSymbol(let name):
            drawSymbol(name: name, in: rect, color: palette.foreground)
        case .imageFile(let path):
            let expanded = (path as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                let r = aspectFitRect(image: img, in: rect)
                img.draw(in: r)
            } else {
                drawSymbol(name: "questionmark.square.dashed", in: rect, color: palette.secondary)
            }
        case .textOnly:
            // Nothing — label-only buttons show their label centred.
            break
        }
    }

    private static func drawSymbol(name: String, in rect: CGRect, color: NSColor) {
        guard let raw = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            // Fall back to a placeholder if the symbol name doesn't resolve.
            let fallback = NSImage(systemSymbolName: "square", accessibilityDescription: nil)
            fallback?.draw(in: rect)
            return
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: rect.height * 0.92, weight: .medium)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        let img = raw.withSymbolConfiguration(cfg) ?? raw
        let r = aspectFitRect(image: img, in: rect)
        img.draw(in: r)
    }

    private static func aspectFitRect(image: NSImage, in rect: CGRect) -> CGRect {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return rect }
        let scale = min(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    private static func truncate(_ text: String,
                                 toWidth maxWidth: CGFloat,
                                 attrs: [NSAttributedString.Key: Any]) -> String {
        guard !text.isEmpty else { return text }
        if (text as NSString).size(withAttributes: attrs).width <= maxWidth { return text }
        var result = text
        while result.count > 1,
              ((result + "…") as NSString).size(withAttributes: attrs).width > maxWidth {
            result.removeLast()
        }
        return result + "…"
    }

    private static func drawCentredText(_ text: String, palette: Palette, size: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: palette.secondary,
        ]
        let ns = text as NSString
        let s = ns.size(withAttributes: attrs)
        let x = (CGFloat(NexusProtocol.width) - s.width) / 2
        let y = (CGFloat(NexusProtocol.height) - s.height) / 2
        ns.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    // MARK: Page dots

    private static func drawPageDots(currentIndex: Int,
                                     total: Int,
                                     palette: Palette,
                                     in ctx: CGContext) {
        guard total > 1 else { return }
        let dotSize: CGFloat = 4
        let gap: CGFloat = 5
        let totalWidth = CGFloat(total) * dotSize + CGFloat(total - 1) * gap
        let y: CGFloat = 2
        let startX = CGFloat(NexusProtocol.width) - totalWidth - 6

        for i in 0..<total {
            let x = startX + CGFloat(i) * (dotSize + gap)
            let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
            if i == currentIndex {
                ctx.setFillColor(palette.foreground.cgColor)
                ctx.fillEllipse(in: rect)
            } else {
                ctx.setStrokeColor(palette.secondary.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            }
        }
    }
}
