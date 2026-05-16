import AppKit
import UniformTypeIdentifiers
import NexusCore

// MARK: - Button card (used in the editor's horizontal button strip)

/// A clickable card representing one PageButton, or an "+ Add" affordance.
final class ButtonCardView: NSView {

    var onClick: (() -> Void)?
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onDelete: (() -> Void)?

    private var pageButton: PageButton?
    private var palette: Palette?
    private var isSelected = false
    private var isAdd = false
    private var hovered = false

    private var leftBtn: NSButton!
    private var rightBtn: NSButton!
    private var deleteBtn: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildOverlayButtons()
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(button: PageButton?, palette: Palette, selected: Bool, isAddCard: Bool) {
        self.pageButton = button
        self.palette = palette
        self.isSelected = selected
        self.isAdd = isAddCard
        leftBtn.isHidden = isAddCard || !selected
        rightBtn.isHidden = isAddCard || !selected
        deleteBtn.isHidden = isAddCard || !selected
        needsDisplay = true
    }

    private func buildOverlayButtons() {
        leftBtn = sym("chevron.left", action: #selector(cardMoveLeft))
        rightBtn = sym("chevron.right", action: #selector(cardMoveRight))
        deleteBtn = sym("trash", action: #selector(cardDelete))

        leftBtn.translatesAutoresizingMaskIntoConstraints = false
        rightBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftBtn)
        addSubview(rightBtn)
        addSubview(deleteBtn)
        NSLayoutConstraint.activate([
            leftBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            leftBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            leftBtn.widthAnchor.constraint(equalToConstant: 22),
            leftBtn.heightAnchor.constraint(equalToConstant: 22),

            rightBtn.leadingAnchor.constraint(equalTo: leftBtn.trailingAnchor, constant: 2),
            rightBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            rightBtn.widthAnchor.constraint(equalToConstant: 22),
            rightBtn.heightAnchor.constraint(equalToConstant: 22),

            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            deleteBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            deleteBtn.widthAnchor.constraint(equalToConstant: 22),
            deleteBtn.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func sym(_ name: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.target = self
        btn.action = action
        btn.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        btn.imagePosition = .imageOnly
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.controlSize = .small
        return btn
    }

    @objc private func cardMoveLeft()  { onMoveLeft?() }
    @objc private func cardMoveRight() { onMoveRight?() }
    @objc private func cardDelete()    { onDelete?() }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        // Forward to the card itself unless the click is on a child button.
        let p = convert(event.locationInWindow, from: nil)
        if !isAdd && (leftBtn.frame.contains(p) || rightBtn.frame.contains(p) || deleteBtn.frame.contains(p)) {
            super.mouseDown(with: event)
            return
        }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)

        let bg: NSColor
        if isAdd {
            bg = hovered
                ? NSColor.controlAccentColor.withAlphaComponent(0.10)
                : NSColor(white: 0, alpha: 0.03)
        } else {
            bg = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : (hovered ? NSColor(white: 0, alpha: 0.06) : NSColor(white: 0, alpha: 0.03))
        }
        bg.setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()

        let borderColor: NSColor = isSelected
            ? NSColor.controlAccentColor
            : NSColor.separatorColor
        borderColor.setStroke()
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        path.lineWidth = isSelected ? 2 : 1
        if isAdd {
            let dash: [CGFloat] = [4, 3]
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        path.stroke()

        if isAdd {
            drawAdd(in: r)
        } else if let button = pageButton {
            drawButton(button, in: r)
        }
    }

    private func drawAdd(in rect: CGRect) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor))
        let img = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        let size: CGFloat = 32
        let r = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2 + 4,
                       width: size, height: size)
        img?.draw(in: r)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let s = "Add" as NSString
        let size2 = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: rect.midX - size2.width / 2, y: rect.maxY - 22),
               withAttributes: attrs)
    }

    private func drawButton(_ btn: PageButton, in rect: CGRect) {
        let iconArea = CGRect(x: rect.minX + 8, y: rect.minY + 8,
                              width: rect.width - 16, height: rect.height - 36)
        drawIcon(btn.icon, in: iconArea)

        let label = btn.label.isEmpty ? "—" : btn.label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: btn.label.isEmpty ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]
        let truncated = truncate(label, width: rect.width - 12, attrs: attrs)
        let s = (truncated as NSString)
        let sw = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: rect.midX - sw.width / 2, y: rect.maxY - 30),
               withAttributes: attrs)
    }

    private func drawIcon(_ icon: ButtonIcon, in rect: CGRect) {
        let tint = NSColor.labelColor
        switch icon {
        case .sfSymbol(let name):
            let cfg = NSImage.SymbolConfiguration(pointSize: rect.height * 0.7, weight: .medium)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: tint))
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: nil)
            let configured = symbol?.withSymbolConfiguration(cfg)
            let dest = aspectFit(size: configured?.size ?? rect.size, in: rect)
            configured?.draw(in: dest)
        case .imageFile(let path):
            let expanded = (path as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                img.draw(in: aspectFit(size: img.size, in: rect))
            }
        case .animatedFile(let path):
            // Show a stale poster frame in the editor card — it doesn't
            // animate, but it tells you what's loaded.
            if let icon = AnimatedIconCache.shared.load(path: path),
               let cg = icon.frame(at: 0) {
                let img = NSImage(cgImage: cg,
                                  size: NSSize(width: cg.width, height: cg.height))
                img.draw(in: aspectFit(size: img.size, in: rect))
            } else {
                let cfg = NSImage.SymbolConfiguration(pointSize: rect.height * 0.55,
                                                     weight: .regular)
                    .applying(NSImage.SymbolConfiguration(hierarchicalColor:
                                                          NSColor.tertiaryLabelColor))
                let icon = NSImage(systemSymbolName: "play.rectangle.on.rectangle",
                                   accessibilityDescription: nil)?
                    .withSymbolConfiguration(cfg)
                icon?.draw(in: aspectFit(size: icon?.size ?? rect.size, in: rect))
            }
        case .textOnly:
            break
        }
    }

    private func aspectFit(size: NSSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    private func truncate(_ s: String, width: CGFloat,
                          attrs: [NSAttributedString.Key: Any]) -> String {
        if (s as NSString).size(withAttributes: attrs).width <= width { return s }
        var t = s
        while t.count > 1, ((t + "…") as NSString).size(withAttributes: attrs).width > width {
            t.removeLast()
        }
        return t + "…"
    }
}

// MARK: - Button inspector view

/// Form for editing a single PageButton: icon kind/value, label, action type
/// + contextual fields. Calls `onChange` whenever any field commits.
final class ButtonInspectorView: NSView {

    var onChange: ((PageButton) -> Void)?

    var button: PageButton? {
        didSet { rebuild() }
    }

    // Persistent controls
    private var rootStack: NSStackView!
    private var labelField: NSTextField!
    private var iconKindPopup: NSPopUpButton!
    private var iconValueField: NSTextField!
    private var iconChooseFileButton: NSButton!
    private var iconPreview: NSImageView!
    private var iconRow: NSStackView!
    private var actionKindPopup: NSPopUpButton!
    private var actionDetailHost: NSStackView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildForm()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildForm() {
        rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        // Label
        labelField = NSTextField()
        labelField.placeholderString = "Button label (optional)"
        labelField.delegate = self
        labelField.widthAnchor.constraint(equalToConstant: 340).isActive = true
        rootStack.addArrangedSubview(row(label: "Label:", control: labelField))

        // Icon kind
        iconKindPopup = NSPopUpButton()
        for k in ButtonIcon.Kind.allCases {
            iconKindPopup.addItem(withTitle: k.rawValue)
            iconKindPopup.lastItem?.representedObject = k
        }
        iconKindPopup.target = self
        iconKindPopup.action = #selector(iconKindChanged)

        iconValueField = NSTextField()
        iconValueField.placeholderString = "e.g. globe, music.note.house, etc."
        iconValueField.delegate = self
        iconValueField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        iconChooseFileButton = NSButton(title: "Choose Image…",
                                        target: self, action: #selector(chooseIconFile))

        iconPreview = NSImageView()
        iconPreview.imageScaling = .scaleProportionallyDown
        iconPreview.wantsLayer = true
        iconPreview.layer?.cornerRadius = 6
        iconPreview.layer?.backgroundColor = NSColor(white: 0, alpha: 0.06).cgColor
        iconPreview.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iconPreview.heightAnchor.constraint(equalToConstant: 40).isActive = true

        iconRow = NSStackView(views: [iconKindPopup, iconValueField,
                                      iconChooseFileButton, iconPreview])
        iconRow.orientation = .horizontal
        iconRow.spacing = 8
        rootStack.addArrangedSubview(row(label: "Icon:", control: iconRow))

        let symbolHint = NSTextField(labelWithString:
            "SF Symbol names come from Apple's SF Symbols app (free). Example: heart.fill, globe, flame.")
        symbolHint.font = NSFont.systemFont(ofSize: 11)
        symbolHint.textColor = .tertiaryLabelColor
        rootStack.addArrangedSubview(row(label: "", control: symbolHint))

        // Divider
        rootStack.addArrangedSubview(divider())

        // Action kind
        actionKindPopup = NSPopUpButton()
        for k in ButtonAction.Kind.allCases {
            actionKindPopup.addItem(withTitle: k.rawValue)
            actionKindPopup.lastItem?.representedObject = k
        }
        actionKindPopup.target = self
        actionKindPopup.action = #selector(actionKindChanged)
        actionKindPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        rootStack.addArrangedSubview(row(label: "Action:", control: actionKindPopup))

        // Action detail host (swapped per kind)
        actionDetailHost = NSStackView()
        actionDetailHost.orientation = .vertical
        actionDetailHost.spacing = 8
        actionDetailHost.alignment = .leading
        rootStack.addArrangedSubview(row(label: "", control: actionDetailHost))
    }

    private func divider() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 600).isActive = true
        return v
    }

    private func row(label: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        let lbl = NSTextField(labelWithString: label)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 70).isActive = true
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }

    // MARK: Rebuild on selection change

    private func rebuild() {
        guard let button else { return }

        labelField.stringValue = button.label

        // Icon
        let kind = button.icon.kind
        if let idx = ButtonIcon.Kind.allCases.firstIndex(of: kind) {
            iconKindPopup.selectItem(at: idx)
        }
        switch button.icon {
        case .sfSymbol(let name):
            iconValueField.stringValue = name
            iconValueField.placeholderString = "e.g. globe, music.note.house, etc."
            iconValueField.isHidden = false
            iconChooseFileButton.title = "Choose Image…"
            iconChooseFileButton.action = #selector(chooseIconFile)
            iconChooseFileButton.isHidden = true
        case .imageFile(let path):
            iconValueField.stringValue = path
            iconValueField.placeholderString = "/path/to/icon.png"
            iconValueField.isHidden = false
            iconChooseFileButton.title = "Choose Image…"
            iconChooseFileButton.action = #selector(chooseIconFile)
            iconChooseFileButton.isHidden = false
        case .animatedFile(let path):
            iconValueField.stringValue = path
            iconValueField.placeholderString = "/path/to/clip.gif or .mp4"
            iconValueField.isHidden = false
            iconChooseFileButton.title = "Choose Clip…"
            iconChooseFileButton.action = #selector(chooseAnimatedFile)
            iconChooseFileButton.isHidden = false
        case .textOnly:
            iconValueField.stringValue = ""
            iconValueField.isHidden = true
            iconChooseFileButton.isHidden = true
        }
        refreshIconPreview()

        // Action
        if let idx = ButtonAction.Kind.allCases.firstIndex(of: button.action.kind) {
            actionKindPopup.selectItem(at: idx)
        }
        rebuildActionDetail()
    }

    // MARK: Field actions

    @objc private func iconKindChanged() {
        guard var b = button,
              let kind = iconKindPopup.selectedItem?.representedObject as? ButtonIcon.Kind else { return }
        if b.icon.kind == kind { return }
        switch kind {
        case .sfSymbol:     b.icon = .sfSymbol(name: "star")
        case .imageFile:    b.icon = .imageFile(path: "")
        case .animatedFile: b.icon = .animatedFile(path: "")
        case .textOnly:     b.icon = .textOnly
        }
        button = b
        onChange?(b)
    }

    @objc private func chooseIconFile() {
        let panel = NSOpenPanel()
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png, .jpeg, .image]
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var b = button else { return }
        let stable = ResourceStore.adopt(url)
        b.icon = .imageFile(path: stable)
        button = b
        onChange?(b)
    }

    @objc private func chooseAnimatedFile() {
        let panel = NSOpenPanel()
        if #available(macOS 11.0, *) {
            // GIF / APNG via .image; MP4 / MOV via UTType.movie. WebM (no
            // native macOS UTType) is picked through `.data` and auto-converted
            // by ClipImporter via ffmpeg.
            panel.allowedContentTypes = [.gif, .png, .image,
                                         .movie, .video, .quickTimeMovie, .mpeg4Movie,
                                         .data]
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var b = button else { return }

        switch ClipImporter.adopt(url) {
        case .success(let stable):
            AnimatedIconCache.shared.invalidate(path: stable)
            b.icon = .animatedFile(path: stable)
            button = b
            onChange?(b)
        case .failure(let err):
            presentClipImportError(err, sourceURL: url)
        }
    }

    private func presentClipImportError(_ err: ClipImporter.ImportError, sourceURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch err {
        case .webmNeedsFfmpeg:
            alert.messageText = "WebM clips need ffmpeg"
            alert.informativeText =
                "macOS can't decode WebM natively. Install ffmpeg with Homebrew:\n\n" +
                "    brew install ffmpeg\n\n" +
                "Then pick the clip again — Nexus Bar will auto-transcode it to MP4."
        case .ffmpegFailed(let stderr):
            alert.messageText = "Couldn't transcode the clip"
            alert.informativeText = "ffmpeg failed for \(sourceURL.lastPathComponent):\n\n\(stderr)"
        case .copyFailed(let underlying):
            alert.messageText = "Couldn't import the clip"
            alert.informativeText = underlying.localizedDescription
        }
        alert.runModal()
    }

    fileprivate func iconValueCommitted() {
        guard var b = button else { return }
        let v = iconValueField.stringValue
        switch b.icon {
        case .sfSymbol:      b.icon = .sfSymbol(name: v)
        case .imageFile:     b.icon = .imageFile(path: v)
        case .animatedFile:  b.icon = .animatedFile(path: v)
        case .textOnly:      break
        }
        button = b
        onChange?(b)
    }

    fileprivate func labelCommitted() {
        guard var b = button else { return }
        b.label = labelField.stringValue
        // Re-apply directly (don't rebuild, the field is the source of truth).
        self.button = b
        onChange?(b)
    }

    private func refreshIconPreview() {
        guard let button else { iconPreview.image = nil; return }
        switch button.icon {
        case .sfSymbol(let name):
            let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))
            iconPreview.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
                ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: nil)
        case .imageFile(let path):
            let expanded = (path as NSString).expandingTildeInPath
            iconPreview.image = NSImage(contentsOfFile: expanded)
        case .animatedFile(let path):
            if let icon = AnimatedIconCache.shared.load(path: path),
               let cg = icon.frame(at: 0) {
                iconPreview.image = NSImage(cgImage: cg,
                                            size: NSSize(width: cg.width, height: cg.height))
            } else {
                iconPreview.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle",
                                            accessibilityDescription: nil)
            }
        case .textOnly:
            iconPreview.image = nil
        }
    }

    // MARK: Action detail panel

    @objc private func actionKindChanged() {
        guard var b = button,
              let kind = actionKindPopup.selectedItem?.representedObject as? ButtonAction.Kind else { return }
        if b.action.kind == kind { return }
        b.action = .empty(for: kind)
        button = b
        onChange?(b)
    }

    private func rebuildActionDetail() {
        actionDetailHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let button else { return }

        switch button.action {
        case .none, .nextPage, .previousPage:
            let info = NSTextField(labelWithString:
                button.action.kind == .nextPage ? "Tapping this button flips to the next page."
                : button.action.kind == .previousPage ? "Tapping this button flips to the previous page."
                : "Tapping this button does nothing.")
            info.font = NSFont.systemFont(ofSize: 11)
            info.textColor = .secondaryLabelColor
            actionDetailHost.addArrangedSubview(info)

        case .launchApp(let bundleId, let display):
            actionDetailHost.addArrangedSubview(makeAppPicker(bundleId: bundleId, display: display))

        case .openURL(let url):
            let field = NSTextField(string: url)
            field.placeholderString = "https://example.com"
            field.widthAnchor.constraint(equalToConstant: 380).isActive = true
            field.delegate = self
            field.identifier = NSUserInterfaceItemIdentifier("openURL")
            actionDetailHost.addArrangedSubview(captioned("URL:", field))

        case .runShortcut(let name):
            let field = NSTextField(string: name)
            field.placeholderString = "Name of a Shortcut from the Shortcuts app"
            field.widthAnchor.constraint(equalToConstant: 380).isActive = true
            field.delegate = self
            field.identifier = NSUserInterfaceItemIdentifier("runShortcut")
            actionDetailHost.addArrangedSubview(captioned("Shortcut:", field))

        case .runScript(let path, let args):
            let pathField = NSTextField(string: path)
            pathField.placeholderString = "/path/to/script.sh (or executable)"
            pathField.widthAnchor.constraint(equalToConstant: 320).isActive = true
            pathField.delegate = self
            pathField.identifier = NSUserInterfaceItemIdentifier("scriptPath")
            let choose = NSButton(title: "Choose…",
                                  target: self, action: #selector(chooseScript))
            let pathRow = NSStackView(views: [pathField, choose])
            pathRow.spacing = 8
            actionDetailHost.addArrangedSubview(captioned("Executable:", pathRow))

            let argField = NSTextField(string: args.joined(separator: " "))
            argField.placeholderString = "space-separated arguments"
            argField.widthAnchor.constraint(equalToConstant: 380).isActive = true
            argField.delegate = self
            argField.identifier = NSUserInterfaceItemIdentifier("scriptArgs")
            actionDetailHost.addArrangedSubview(captioned("Arguments:", argField))

        case .sendKeystroke(_, _, let label):
            let displayLabel = NSTextField(labelWithString: label.isEmpty ? "(no key recorded)" : label)
            displayLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            displayLabel.textColor = label.isEmpty ? .secondaryLabelColor : .labelColor

            let recordBtn = NSButton(title: "Record Keystroke…",
                                     target: self, action: #selector(recordKeystroke(_:)))
            recordBtn.bezelStyle = .rounded

            let row = NSStackView(views: [displayLabel, recordBtn])
            row.spacing = 14
            actionDetailHost.addArrangedSubview(captioned("Keystroke:", row))

            let hint = NSTextField(wrappingLabelWithString:
                "Click Record, then press the key combination you want this button to send. " +
                "Sending keystrokes needs Accessibility permission the first time.")
            hint.font = NSFont.systemFont(ofSize: 11)
            hint.textColor = .tertiaryLabelColor
            hint.preferredMaxLayoutWidth = 540
            actionDetailHost.addArrangedSubview(hint)

        case .mediaKey(let current):
            let popup = NSPopUpButton()
            for k in MediaKey.allCases {
                popup.addItem(withTitle: k.displayName)
                popup.lastItem?.representedObject = k
            }
            if let idx = MediaKey.allCases.firstIndex(of: current) {
                popup.selectItem(at: idx)
            }
            popup.target = self
            popup.action = #selector(mediaKeyChanged(_:))
            popup.widthAnchor.constraint(equalToConstant: 200).isActive = true
            actionDetailHost.addArrangedSubview(captioned("Key:", popup))
        }
    }

    private func captioned(_ caption: String, _ control: NSView) -> NSView {
        let lbl = NSTextField(labelWithString: caption)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let stack = NSStackView(views: [lbl, control])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .firstBaseline
        return stack
    }

    private func makeAppPicker(bundleId: String, display: String) -> NSView {
        let iconView = NSImageView()
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            iconView.image = NSImage(systemSymbolName: "app.dashed",
                                     accessibilityDescription: nil)
        }

        let titleLabel = NSTextField(labelWithString: display.isEmpty ? "No app selected" : display)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let bundleLabel = NSTextField(labelWithString: bundleId.isEmpty ? "" : "\(bundleId)")
        bundleLabel.font = NSFont.systemFont(ofSize: 11)
        bundleLabel.textColor = .secondaryLabelColor

        let info = NSStackView(views: [titleLabel, bundleLabel])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 1

        let chooseBtn = NSButton(title: "Choose App…",
                                 target: self, action: #selector(chooseApp))
        let row = NSStackView(views: [iconView, info, chooseBtn])
        row.spacing = 10
        return row
    }

    // MARK: Action field commits

    @objc private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bid = bundle.bundleIdentifier else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
        guard var b = button else { return }
        b.action = .launchApp(bundleId: bid, displayName: name)
        button = b
        onChange?(b)
    }

    @objc private func chooseScript() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var b = button, case .runScript(_, let args) = b.action else { return }
        b.action = .runScript(path: url.path, args: args)
        button = b
        onChange?(b)
    }

    @objc private func mediaKeyChanged(_ sender: NSPopUpButton) {
        guard var b = button,
              let key = sender.selectedItem?.representedObject as? MediaKey else { return }
        b.action = .mediaKey(kind: key)
        button = b
        onChange?(b)
    }

    private var recordingMonitor: Any?
    private var recordButton: NSButton?

    @objc private func recordKeystroke(_ sender: NSButton) {
        recordButton = sender
        sender.title = "Press a combo…"
        sender.isEnabled = false
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleRecordedKey(event)
            return nil
        }
        // Safety: stop recording after 8s if nothing pressed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.stopRecording()
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        // Ignore pure-modifier presses (no character glyph).
        let chars = event.charactersIgnoringModifiers ?? ""
        guard !chars.isEmpty else { return }
        let label = modString(mods) + chars.uppercased()
        let cgMods = cgEventFlags(from: mods)
        guard var b = button else { stopRecording(); return }
        b.action = .sendKeystroke(keyCode: event.keyCode,
                                  modifiers: cgMods.rawValue,
                                  label: label)
        button = b
        onChange?(b)
        stopRecording()
    }

    private func stopRecording() {
        if let m = recordingMonitor { NSEvent.removeMonitor(m); recordingMonitor = nil }
        recordButton?.title = "Record Keystroke…"
        recordButton?.isEnabled = true
        recordButton = nil
    }

    private func modString(_ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control)  { s += "⌃" }
        if mods.contains(.option)   { s += "⌥" }
        if mods.contains(.shift)    { s += "⇧" }
        if mods.contains(.command)  { s += "⌘" }
        return s
    }

    private func cgEventFlags(from ns: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if ns.contains(.command) { f.insert(.maskCommand) }
        if ns.contains(.shift)   { f.insert(.maskShift) }
        if ns.contains(.option)  { f.insert(.maskAlternate) }
        if ns.contains(.control) { f.insert(.maskControl) }
        return f
    }
}

// MARK: - Free-layout element inspector

/// Inspector for a `PageElement` (either a widget or a button placed on a
/// free-layout page). Shows the element's frame as four integer fields plus
/// kind-specific controls — for widgets, a kind popup; for buttons, the same
/// `ButtonInspectorView` used in button-grid pages.
final class FreeElementInspectorView: NSView {

    var onElementChanged: ((PageElement) -> Void)?
    var onDeleteRequested: (() -> Void)?

    var element: PageElement? {
        didSet {
            if oldValue == element { return }   // ignore no-op re-sets so typing isn't interrupted
            rebuild()
        }
    }

    // Frame inputs (logical pixel coordinates on the 640×48 canvas).
    private var xField, yField, wField, hField: NSTextField!

    // Kind banner / actions
    private var kindLabel: NSTextField!
    private var deleteButton: NSButton!

    // Widget-mode controls
    private var widgetKindPopup: NSPopUpButton!
    private var widgetSection: NSStackView!

    // Button-mode controls (delegates to ButtonInspectorView)
    private var buttonInspector: ButtonInspectorView!
    private var buttonSection: NSStackView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildForm()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildForm() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        // Header: element kind + delete button
        kindLabel = NSTextField(labelWithString: "")
        kindLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        deleteButton = NSButton(title: "Delete Element",
                                target: self, action: #selector(deleteTapped))
        deleteButton.bezelStyle = .rounded
        let header = NSStackView(views: [kindLabel, NSView(), deleteButton])
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .firstBaseline
        header.widthAnchor.constraint(equalToConstant: 620).isActive = true
        root.addArrangedSubview(header)

        // Frame row
        xField = makeIntField("X", id: "free.x")
        yField = makeIntField("Y", id: "free.y")
        wField = makeIntField("W", id: "free.w")
        hField = makeIntField("H", id: "free.h")
        let frameRow = NSStackView(views: [
            captioned("Frame:", row(label: "X", field: xField)),
            row(label: "Y", field: yField),
            row(label: "W", field: wField),
            row(label: "H", field: hField),
        ])
        frameRow.orientation = .horizontal
        frameRow.spacing = 12
        frameRow.alignment = .firstBaseline
        root.addArrangedSubview(frameRow)

        let hint = NSTextField(labelWithString:
            "Canvas is 640 × 48. Drag the element on the preview above or fine-tune here. " +
            "Arrow keys nudge by 1 px (⇧+arrow = 8 px). Backspace deletes.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0
        hint.preferredMaxLayoutWidth = 600
        root.addArrangedSubview(hint)

        // Widget section
        widgetKindPopup = NSPopUpButton()
        for k in WidgetKind.allCases {
            widgetKindPopup.addItem(withTitle: k.displayName)
            widgetKindPopup.lastItem?.representedObject = k
        }
        widgetKindPopup.target = self
        widgetKindPopup.action = #selector(widgetKindChanged)
        widgetKindPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let widgetRow = NSStackView(views: [
            NSTextField(labelWithString: "Widget:"), widgetKindPopup,
        ])
        widgetRow.orientation = .horizontal
        widgetRow.spacing = 10
        widgetRow.alignment = .firstBaseline

        widgetSection = NSStackView(views: [widgetRow])
        widgetSection.orientation = .vertical
        widgetSection.alignment = .leading
        widgetSection.spacing = 10
        root.addArrangedSubview(widgetSection)

        // Button section
        buttonInspector = ButtonInspectorView()
        buttonInspector.onChange = { [weak self] btn in
            guard let self, var el = self.element, case .button = el.kind else { return }
            el.kind = .button(btn)
            self.element = el            // refresh fields (won't rebuild much since kind matches)
            self.onElementChanged?(el)
        }
        buttonInspector.translatesAutoresizingMaskIntoConstraints = false

        buttonSection = NSStackView(views: [buttonInspector])
        buttonSection.orientation = .vertical
        buttonSection.alignment = .leading
        buttonSection.spacing = 0
        root.addArrangedSubview(buttonSection)
    }

    private func makeIntField(_ placeholder: String, id: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: 56).isActive = true
        f.identifier = NSUserInterfaceItemIdentifier(id)
        f.delegate = self
        return f
    }

    private func row(label: String, field: NSTextField) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let s = NSStackView(views: [l, field])
        s.orientation = .horizontal
        s.spacing = 4
        s.alignment = .firstBaseline
        return s
    }

    private func captioned(_ caption: String, _ control: NSView) -> NSView {
        let lbl = NSTextField(labelWithString: caption)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 55).isActive = true
        let stack = NSStackView(views: [lbl, control])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .firstBaseline
        return stack
    }

    private func rebuild() {
        guard let element else { return }

        let r = element.frame
        xField.stringValue = String(Int(r.x))
        yField.stringValue = String(Int(r.y))
        wField.stringValue = String(Int(r.width))
        hField.stringValue = String(Int(r.height))

        switch element.kind {
        case .widget(let kind):
            kindLabel.stringValue = "Widget — \(kind.displayName)"
            widgetSection.isHidden = false
            buttonSection.isHidden = true
            if let idx = WidgetKind.allCases.firstIndex(of: kind) {
                widgetKindPopup.selectItem(at: idx)
            }
        case .button(let btn):
            kindLabel.stringValue = "Button"
            widgetSection.isHidden = true
            buttonSection.isHidden = false
            buttonInspector.button = btn
        }
    }

    @objc private func widgetKindChanged() {
        guard var el = element,
              let kind = widgetKindPopup.selectedItem?.representedObject as? WidgetKind,
              case .widget = el.kind else { return }
        el.kind = .widget(kind)
        element = el
        onElementChanged?(el)
    }

    @objc private func deleteTapped() {
        onDeleteRequested?()
    }
}

extension FreeElementInspectorView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              var el = element else { return }
        let v = CGFloat(Int(field.stringValue) ?? 0)
        var r = el.frame
        switch field.identifier?.rawValue {
        case "free.x": r.x = v
        case "free.y": r.y = v
        case "free.w": r.width = v
        case "free.h": r.height = v
        default: return
        }
        // Soft clamp so out-of-bounds typing still produces a valid element.
        let cw = CGFloat(NexusProtocol.width)
        let ch = CGFloat(NexusProtocol.height)
        r.width  = max(6, min(cw, r.width))
        r.height = max(6, min(ch, r.height))
        r.x      = max(0, min(cw - r.width,  r.x))
        r.y      = max(0, min(ch - r.height, r.y))
        el.frame = r
        element = el                     // re-displays the clamped values
        onElementChanged?(el)
    }
}

// MARK: - NSTextFieldDelegate for ButtonInspectorView fields

extension ButtonInspectorView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }

        if field === labelField {
            labelCommitted(); return
        }
        if field === iconValueField {
            iconValueCommitted()
            refreshIconPreview()
            return
        }

        guard var b = button else { return }
        switch field.identifier?.rawValue {
        case "openURL":
            b.action = .openURL(url: field.stringValue)
        case "runShortcut":
            b.action = .runShortcut(name: field.stringValue)
        case "scriptPath":
            if case .runScript(_, let args) = b.action {
                b.action = .runScript(path: field.stringValue, args: args)
            }
        case "scriptArgs":
            if case .runScript(let path, _) = b.action {
                let args = field.stringValue
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                b.action = .runScript(path: path, args: args)
            }
        default:
            return
        }
        button = b
        onChange?(b)
    }
}
