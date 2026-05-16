import AppKit
import NexusCore

/// Interactive canvas for editing a free-layout page.
///
/// The canvas keeps its logical coordinate space at 640×48 (matching the
/// device) and renders the page through `PageRenderer.renderFreeLayout` to
/// keep the editor pixel-identical to what the panel shows. Selection,
/// dragging, and resizing are overlaid in *view* coordinates so the
/// interaction targets are large enough to grab with a mouse.
///
/// The caller drives the canvas with `update(page:selectedElementId:)` and
/// receives changes via the `onPageChanged` / `onSelectionChanged` callbacks.
/// The canvas never mutates the model itself; it produces a new `Page` on each
/// change and asks the caller to commit it.
final class FreeLayoutCanvasView: NSView {

    // MARK: Callbacks

    var onPageChanged: ((Page) -> Void)?
    var onSelectionChanged: ((UUID?) -> Void)?

    // MARK: Inputs

    private var page: Page?
    private var selectedId: UUID?
    private var palette: Palette = Settings.Theme.dark.palette
    private var timeFormat: Settings.TimeFormat = .twentyFour
    private var showSeconds: Bool = true
    private var backgroundFrame: [UInt8]?
    private var backgroundDim: Int = 0
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()

    // MARK: Drag state

    private enum DragMode {
        case move(originalFrame: CGRect, startPoint: CGPoint)
        case resize(corner: Corner, originalFrame: CGRect, startPoint: CGPoint)
    }
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private var dragMode: DragMode?

    // MARK: Geometry

    /// Logical → view scale factor (uniform). 640 logical = bounds.width.
    private var scale: CGFloat {
        guard bounds.width > 0 else { return 1 }
        return bounds.width / CGFloat(NexusProtocol.width)
    }
    private var handleSizeView: CGFloat { 10 }   // size of corner handles in screen pixels

    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 640, height: 48) }

    // MARK: Public update

    /// Refresh inputs / theme / background so the canvas redraws.
    func update(page: Page?,
                selectedElementId: UUID?,
                palette: Palette,
                timeFormat: Settings.TimeFormat,
                showSeconds: Bool,
                background: [UInt8]?,
                backgroundDim: Int) {
        self.page = page
        self.selectedId = selectedElementId
        self.palette = palette
        self.timeFormat = timeFormat
        self.showSeconds = showSeconds
        self.backgroundFrame = background
        self.backgroundDim = backgroundDim
        needsDisplay = true
    }

    /// Pulse — the canvas re-renders on a timer so live widgets animate.
    func tick() {
        cpu.sample()
        memory.sample()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let page else {
            drawPlaceholder()
            return
        }

        // Render the current page through the same renderer the device uses.
        cpu.sample()
        memory.sample()
        let inputs = RenderInputs(date: Date(),
                                  cpuLoad: cpu.usage > 0 ? cpu.usage : 0.42,
                                  memUsage: memory.usage > 0 ? memory.usage : 0.58,
                                  memUsedGB: memory.usedGB,
                                  memTotalGB: memory.totalGB)
        let animTime = Date().timeIntervalSinceReferenceDate

        if let bytes = try? PageRenderer.renderFreeLayout(
                page: page,
                palette: palette,
                inputs: inputs,
                timeFormat: timeFormat,
                showSeconds: showSeconds,
                background: backgroundFrame,
                backgroundDim: backgroundDim,
                pressedElementId: nil,
                pageIndex: 0,
                pageCount: 1,
                animationTime: animTime),
           let cg = NexusImage.cgImage(from: bytes) {
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.interpolationQuality = .none
                ctx.draw(cg, in: bounds)
                ctx.restoreGState()
            }
        }

        // Overlay selection / handles for the selected element.
        if let id = selectedId, let el = page.elements.first(where: { $0.id == id }) {
            let viewRect = viewRectFor(logical: el.frame.cgRect)
            drawSelectionOverlay(viewRect, kind: el.kind)
        }
    }

    private func drawPlaceholder() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let s = "(no page selected)" as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height - size.height) / 2),
               withAttributes: attrs)
    }

    private func drawSelectionOverlay(_ rect: NSRect, kind: ElementKind) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Outline.
        let accent = NSColor.controlAccentColor
        accent.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        path.lineWidth = 2
        path.stroke()

        // Corner handles (small squares centred on each corner).
        let h = handleSizeView
        let corners: [NSPoint] = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]
        for p in corners {
            let r = NSRect(x: p.x - h / 2, y: p.y - h / 2, width: h, height: h)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            accent.setStroke()
            let stroke = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            stroke.lineWidth = 1.5
            stroke.stroke()
        }

        // Small type chip in the corner so widgets are distinguishable from
        // tappable buttons at a glance.
        let chip = kind.typeLabel
        let chipAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let chipSize = (chip as NSString).size(withAttributes: chipAttrs)
        let chipBg = NSRect(x: rect.maxX - chipSize.width - 8,
                            y: rect.minY - chipSize.height - 4,
                            width: chipSize.width + 6,
                            height: chipSize.height + 2)
        accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: chipBg, xRadius: 3, yRadius: 3).fill()
        (chip as NSString).draw(at: NSPoint(x: chipBg.minX + 3, y: chipBg.minY + 1),
                                withAttributes: chipAttrs)
    }

    // MARK: Coordinate mapping

    /// Convert a logical canvas rect (top-left origin, 640×48) into the view's
    /// flipped(false) bounds (bottom-left origin). NSView default `isFlipped =
    /// false` so y grows upward.
    private func viewRectFor(logical: CGRect) -> NSRect {
        let s = scale
        return NSRect(x: logical.minX * s,
                      y: bounds.height - (logical.maxY * s),
                      width: logical.width * s,
                      height: logical.height * s)
    }

    /// Convert a view point (bottom-left origin) into logical canvas coords.
    private func logicalPoint(from view: NSPoint) -> CGPoint {
        let s = scale
        return CGPoint(x: view.x / s,
                       y: (bounds.height - view.y) / s)
    }

    /// Locate the top-most element whose view-rect (including a small grab
    /// margin) contains the point. Returns nil when missing.
    private func hitElement(at viewPoint: NSPoint) -> PageElement? {
        guard let page else { return nil }
        for el in page.elements.reversed() {
            let r = viewRectFor(logical: el.frame.cgRect).insetBy(dx: -4, dy: -4)
            if r.contains(viewPoint) { return el }
        }
        return nil
    }

    private func hitCorner(of element: PageElement, at viewPoint: NSPoint) -> Corner? {
        let r = viewRectFor(logical: element.frame.cgRect)
        let h = handleSizeView + 6  // generous grab radius
        let corners: [(Corner, NSPoint)] = [
            (.topLeft,     NSPoint(x: r.minX, y: r.maxY)),
            (.topRight,    NSPoint(x: r.maxX, y: r.maxY)),
            (.bottomLeft,  NSPoint(x: r.minX, y: r.minY)),
            (.bottomRight, NSPoint(x: r.maxX, y: r.minY)),
        ]
        for (c, p) in corners {
            if abs(p.x - viewPoint.x) <= h / 2, abs(p.y - viewPoint.y) <= h / 2 { return c }
        }
        return nil
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)

        // If we have a selected element, see if the click is on one of its handles first.
        if let id = selectedId,
           let el = page?.elements.first(where: { $0.id == id }),
           let corner = hitCorner(of: el, at: p) {
            dragMode = .resize(corner: corner,
                               originalFrame: el.frame.cgRect,
                               startPoint: logicalPoint(from: p))
            return
        }

        if let el = hitElement(at: p) {
            if selectedId != el.id {
                selectedId = el.id
                onSelectionChanged?(el.id)
                needsDisplay = true
            }
            dragMode = .move(originalFrame: el.frame.cgRect,
                             startPoint: logicalPoint(from: p))
        } else {
            // Empty area — clear selection.
            if selectedId != nil {
                selectedId = nil
                onSelectionChanged?(nil)
                needsDisplay = true
            }
            dragMode = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode = dragMode,
              let id = selectedId,
              var page else { return }
        guard let idx = page.elements.firstIndex(where: { $0.id == id }) else { return }

        let p = convert(event.locationInWindow, from: nil)
        let current = logicalPoint(from: p)
        var newRect: CGRect

        switch mode {
        case .move(let original, let start):
            let dx = current.x - start.x
            let dy = current.y - start.y
            newRect = CGRect(x: original.minX + dx,
                             y: original.minY + dy,
                             width: original.width,
                             height: original.height)
        case .resize(let corner, let original, let start):
            let dx = current.x - start.x
            let dy = current.y - start.y
            switch corner {
            case .topLeft:
                newRect = CGRect(x: original.minX + dx,
                                 y: original.minY + dy,
                                 width: original.width - dx,
                                 height: original.height - dy)
            case .topRight:
                newRect = CGRect(x: original.minX,
                                 y: original.minY + dy,
                                 width: original.width + dx,
                                 height: original.height - dy)
            case .bottomLeft:
                newRect = CGRect(x: original.minX + dx,
                                 y: original.minY,
                                 width: original.width - dx,
                                 height: original.height + dy)
            case .bottomRight:
                newRect = CGRect(x: original.minX,
                                 y: original.minY,
                                 width: original.width + dx,
                                 height: original.height + dy)
            }
        }

        newRect = clamp(newRect)
        page.elements[idx].frame = PageRect(newRect)
        self.page = page
        onPageChanged?(page)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
    }

    /// Constrain a rect to integer-pixel coordinates within the 640×48 canvas
    /// with a minimum size of 6×6 logical pixels (smaller than this and you
    /// can't grab it).
    private func clamp(_ r: CGRect) -> CGRect {
        let canvasW = CGFloat(NexusProtocol.width)
        let canvasH = CGFloat(NexusProtocol.height)
        let minSize: CGFloat = 6
        var w = max(minSize, r.width.rounded())
        var h = max(minSize, r.height.rounded())
        var x = r.minX.rounded()
        var y = r.minY.rounded()
        if w > canvasW { w = canvasW }
        if h > canvasH { h = canvasH }
        x = max(0, min(canvasW - w, x))
        y = max(0, min(canvasH - h, y))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Keyboard nudge

    override func keyDown(with event: NSEvent) {
        guard let id = selectedId,
              var page,
              let idx = page.elements.firstIndex(where: { $0.id == id }) else {
            super.keyDown(with: event)
            return
        }
        let shift = event.modifierFlags.contains(.shift)
        let step: CGFloat = shift ? 8 : 1
        var r = page.elements[idx].frame.cgRect

        switch event.keyCode {
        case 123: r.origin.x -= step   // ←
        case 124: r.origin.x += step   // →
        case 125: r.origin.y += step   // ↓  (top-left origin → y increases downward)
        case 126: r.origin.y -= step   // ↑
        case 51, 117:                  // delete / forward-delete
            page.elements.remove(at: idx)
            self.page = page
            selectedId = nil
            onSelectionChanged?(nil)
            onPageChanged?(page)
            needsDisplay = true
            return
        default:
            super.keyDown(with: event)
            return
        }
        r = clamp(r)
        page.elements[idx].frame = PageRect(r)
        self.page = page
        onPageChanged?(page)
        needsDisplay = true
    }
}
