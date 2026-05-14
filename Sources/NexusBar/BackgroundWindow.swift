import AppKit
import UniformTypeIdentifiers
import NexusCore

/// Window for managing the background image: drag-and-drop input, scale-mode
/// picker, dim slider, and a 2× live preview of what the Nexus will show.
final class BackgroundWindowController: NSWindowController, NSWindowDelegate {

    private let settings = Settings.shared
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()

    private var dropZone: ImageDropView!
    private var pathLabel: NSTextField!
    private var modePopup: NSPopUpButton!
    private var dimSlider: NSSlider!
    private var dimLabel: NSTextField!
    private var previewView: NSImageView!
    private var removeButton: NSButton!
    private var chooseButton: NSButton!

    private var previewTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1340, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Background Image"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1340, height: 520)
        self.init(window: window)
        window.delegate = self
        buildContent()
        applyStateFromSettings()
        startPreviewLoop()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(externalSettingsChanged),
                                               name: Settings.changed, object: nil)
    }

    deinit {
        previewTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Layout

    private func buildContent() {
        guard let content = window?.contentView else { return }

        // Preview: 1280×96 (2× device resolution).
        previewView = NSImageView(frame: NSRect(x: 30, y: 380, width: 1280, height: 96))
        previewView.wantsLayer = true
        previewView.layer?.borderColor = NSColor.separatorColor.cgColor
        previewView.layer?.borderWidth = 1
        previewView.layer?.cornerRadius = 4
        previewView.imageScaling = .scaleProportionallyDown
        previewView.layer?.magnificationFilter = .nearest
        content.addSubview(previewView)

        let previewCaption = NSTextField(labelWithString: "Live preview (2× actual size, 640×48 device)")
        previewCaption.font = NSFont.systemFont(ofSize: 11)
        previewCaption.textColor = .secondaryLabelColor
        previewCaption.frame = NSRect(x: 30, y: 354, width: 600, height: 18)
        content.addSubview(previewCaption)

        // Drop zone (bottom-left).
        dropZone = ImageDropView(frame: NSRect(x: 30, y: 60, width: 620, height: 240))
        dropZone.onDrop = { [weak self] url in self?.applyImage(at: url) }
        content.addSubview(dropZone)

        // Right column: controls.
        let controls = NSStackView(frame: NSRect(x: 680, y: 60, width: 630, height: 280))
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 16
        content.addSubview(controls)

        // Current path label.
        pathLabel = NSTextField(labelWithString: "No background")
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 2
        pathLabel.preferredMaxLayoutWidth = 600
        controls.addArrangedSubview(labelledRow("Image:", control: pathLabel))

        // Scale mode picker.
        modePopup = NSPopUpButton()
        for m in NexusImage.ScaleMode.allCases {
            modePopup.addItem(withTitle: m.displayName)
            modePopup.lastItem?.representedObject = m
        }
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))
        controls.addArrangedSubview(labelledRow("Scale:", control: modePopup))

        // Dim slider.
        dimSlider = NSSlider(value: 0, minValue: 0, maxValue: 100,
                             target: self, action: #selector(dimChanged(_:)))
        dimSlider.isContinuous = true
        dimSlider.widthAnchor.constraint(equalToConstant: 380).isActive = true
        dimLabel = NSTextField(labelWithString: "0%")
        dimLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dimLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let dimRow = NSStackView(views: [dimSlider, dimLabel])
        dimRow.orientation = .horizontal
        dimRow.spacing = 10
        controls.addArrangedSubview(labelledRow("Dim:", control: dimRow))

        // Buttons.
        chooseButton = NSButton(title: "Choose Image…",
                                target: self, action: #selector(chooseImage))
        chooseButton.bezelStyle = .rounded
        removeButton = NSButton(title: "Remove Background",
                                target: self, action: #selector(removeImage))
        removeButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [chooseButton, removeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        controls.addArrangedSubview(labelledRow("", control: buttons))

        // Hint text.
        let hint = NSTextField(wrappingLabelWithString:
            "Drop an image into the box, or use Choose Image…. The clock and " +
            "stats overlay your image live. Use Dim to darken bright images so " +
            "text stays readable.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 600
        controls.addArrangedSubview(hint)
    }

    private func labelledRow(_ label: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10

        let lbl = NSTextField(labelWithString: label)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }

    // MARK: State

    private func applyStateFromSettings() {
        let path = settings.backgroundImagePath
        pathLabel.stringValue = path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "No background"
        removeButton.isEnabled = path != nil
        if let m = NexusImage.ScaleMode.allCases.firstIndex(of: settings.backgroundScaleMode) {
            modePopup.selectItem(at: m)
        }
        dimSlider.integerValue = settings.backgroundDim
        dimLabel.stringValue = "\(settings.backgroundDim)%"
        dropZone.previewImage = path.flatMap {
            NSImage(contentsOfFile: ($0 as NSString).expandingTildeInPath)
        }
    }

    @objc private func externalSettingsChanged() {
        DispatchQueue.main.async { [weak self] in self?.applyStateFromSettings() }
    }

    // MARK: Live preview

    private func startPreviewLoop() {
        previewTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshPreview()
        }
        RunLoop.main.add(t, forMode: .common)
        previewTimer = t
        refreshPreview()
    }

    private func refreshPreview() {
        cpu.sample(); memory.sample()
        let inputs = RenderInputs(date: Date(),
                                  cpuLoad: cpu.usage > 0 ? cpu.usage : 0.42,
                                  memUsage: memory.usage > 0 ? memory.usage : 0.58,
                                  memUsedGB: memory.usedGB,
                                  memTotalGB: memory.totalGB)

        let bg: [UInt8]?
        if let p = settings.backgroundImagePath {
            let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            bg = (try? NexusImage.loadAsFrame(url: url, mode: settings.backgroundScaleMode))
        } else {
            bg = nil
        }

        do {
            let frame = try LayoutRenderer.render(
                layout: settings.layout,
                inputs: inputs,
                palette: settings.theme.palette,
                timeFormat: settings.timeFormat,
                showSeconds: settings.showSeconds,
                background: bg,
                backgroundDim: settings.backgroundDim
            )
            if let cg = NexusImage.cgImage(from: frame) {
                let img = NSImage(cgImage: cg,
                                  size: NSSize(width: NexusProtocol.width, height: NexusProtocol.height))
                previewView.image = img
            }
        } catch {
            // Silent — preview is best-effort.
        }
    }

    // MARK: Actions

    @objc private func chooseImage() {
        let panel = NSOpenPanel()
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .gif]
        }
        panel.allowsMultipleSelection = false
        panel.message = "Pick an image to use as a background."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyImage(at: url)
    }

    private func applyImage(at url: URL) {
        settings.backgroundImagePath = url.path
        applyStateFromSettings()
        refreshPreview()
    }

    @objc private func removeImage() {
        settings.backgroundImagePath = nil
        applyStateFromSettings()
        refreshPreview()
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.representedObject as? NexusImage.ScaleMode else { return }
        settings.backgroundScaleMode = mode
        refreshPreview()
    }

    @objc private func dimChanged(_ sender: NSSlider) {
        let v = Int(sender.doubleValue.rounded())
        settings.backgroundDim = v
        dimLabel.stringValue = "\(v)%"
        refreshPreview()
    }

    // MARK: Show

    func showAndFront() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
    }

    func windowWillClose(_ notification: Notification) {
        previewTimer?.invalidate()
        previewTimer = nil
    }
}

// MARK: - Drop zone view

/// An NSView that accepts file URL drag-and-drops and shows a preview of the
/// currently-selected image (or a placeholder hint when empty).
final class ImageDropView: NSView {

    var onDrop: ((URL) -> Void)?

    var previewImage: NSImage? {
        didSet { needsDisplay = true }
    }

    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        if #available(macOS 10.13, *) {
            registerForDraggedTypes([.fileURL])
        } else {
            registerForDraggedTypes([NSPasteboard.PasteboardType("public.file-url")])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.10)
            : NSColor(white: 0, alpha: 0.04)
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        path.fill()

        let borderColor: NSColor = isHighlighted ? .controlAccentColor : NSColor.separatorColor
        borderColor.setStroke()
        path.lineWidth = isHighlighted ? 2 : 1
        let dash: [CGFloat] = [6, 4]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.stroke()

        if let img = previewImage {
            // Draw the image preview at the top, fitting the box.
            let target = bounds.insetBy(dx: 24, dy: 24)
            let imgSize = img.size
            guard imgSize.width > 0, imgSize.height > 0 else { return }
            let scale = min(target.width / imgSize.width, target.height / imgSize.height)
            let drawSize = NSSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = NSPoint(x: target.midX - drawSize.width / 2,
                                 y: target.midY - drawSize.height / 2)
            img.draw(in: NSRect(origin: origin, size: drawSize))
        } else {
            let title = "Drop an image here"
            let subtitle = "PNG, JPEG, HEIC, GIF, TIFF — any size"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let tSize = (title as NSString).size(withAttributes: titleAttrs)
            let sSize = (subtitle as NSString).size(withAttributes: subAttrs)
            (title as NSString).draw(at: NSPoint(x: bounds.midX - tSize.width / 2,
                                                 y: bounds.midY + 4),
                                     withAttributes: titleAttrs)
            (subtitle as NSString).draw(at: NSPoint(x: bounds.midX - sSize.width / 2,
                                                    y: bounds.midY - sSize.height - 4),
                                        withAttributes: subAttrs)
        }
    }

    // MARK: Drag handling

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasImageURL(in: sender) else { return [] }
        isHighlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        guard let url = readImageURL(from: sender) else { return false }
        onDrop?(url)
        return true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasImageURL(in: sender)
    }

    private func hasImageURL(in info: NSDraggingInfo) -> Bool {
        readImageURL(from: info) != nil
    }

    private func readImageURL(from info: NSDraggingInfo) -> URL? {
        let pb = info.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                         options: [.urlReadingFileURLsOnly: true])
                as? [URL], let url = urls.first else { return nil }
        if #available(macOS 11.0, *) {
            guard let utype = UTType(filenameExtension: url.pathExtension.lowercased()),
                  utype.conforms(to: .image) else { return nil }
        }
        return url
    }
}
