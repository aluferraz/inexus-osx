import AppKit
import NexusCore

/// Multi-pane editor for the swipe-cycle pages. Layout:
///
///     ┌──────────┬──────────────────────────────────────────┐
///     │ Sidebar  │ Live preview (2×)                        │
///     │ (pages)  ├──────────────────────────────────────────┤
///     │          │ Page name + kind                         │
///     │          ├──────────────────────────────────────────┤
///     │          │ Button strip (selectable cards + Add)    │
///     │          ├──────────────────────────────────────────┤
///     │          │ Button inspector (icon / label / action) │
///     └──────────┴──────────────────────────────────────────┘
final class PagesEditorWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Stores

    private let store = PagesStore.shared
    private let settings = Settings.shared

    // MARK: Selection state

    private var selectedPageId: UUID? {
        didSet { onSelectionChanged() }
    }
    private var selectedButtonId: UUID? {
        didSet { onSelectionChanged() }
    }

    // MARK: Views

    private var sidebarTable: NSTableView!
    private var sidebarScroll: NSScrollView!
    private var previewImageView: NSImageView!
    private var pageNameField: NSTextField!
    private var pageKindPopup: NSPopUpButton!
    private var pageHeaderHost: NSStackView!
    private var buttonStrip: NSStackView!
    private var inspector: ButtonInspectorView!
    private var emptyStateLabel: NSTextField!
    private var inspectorScroll: NSScrollView!

    // Live preview timer (so the clock updates in the status preview).
    private var previewTimer: Timer?
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()

    // MARK: Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1340, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Pages Editor"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1340, height: 680)
        self.init(window: window)
        window.delegate = self
        buildContent()
        store.pages.first.map { selectedPageId = $0.id }
        reloadSidebar()
        applyState()
        startPreviewLoop()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(externalPagesChanged),
                                               name: PagesStore.changed, object: nil)
    }

    deinit {
        previewTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func showAndFront() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
    }

    func windowWillClose(_ notification: Notification) {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    // MARK: Layout

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let sidebar = buildSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let main = buildMainPane()
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),

            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
    }

    // MARK: Sidebar

    private func buildSidebar() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let header = NSTextField(labelWithString: "Pages")
        header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let table = NSTableView()
        table.style = .plain
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.rowHeight = 38
        table.headerView = nil
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        col.width = 200
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(sidebarSelectionChanged)
        table.allowsMultipleSelection = false
        sidebarTable = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        sidebarScroll = scroll
        container.addSubview(scroll)

        // Button row at the bottom: add / remove / move up / move down.
        let addButton = imageButton(symbol: "plus", selector: #selector(addPage), tooltip: "Add page")
        let removeButton = imageButton(symbol: "minus", selector: #selector(removeSelectedPage), tooltip: "Remove page")
        let upButton = imageButton(symbol: "arrow.up", selector: #selector(moveSelectedPageUp), tooltip: "Move up")
        let downButton = imageButton(symbol: "arrow.down", selector: #selector(moveSelectedPageDown), tooltip: "Move down")
        let resetButton = imageButton(symbol: "arrow.uturn.backward", selector: #selector(resetToDefaults), tooltip: "Reset to defaults")

        let buttonRow = NSStackView(views: [addButton, removeButton, upButton, downButton, NSView(), resetButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 4
        buttonRow.distribution = .fill
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),

            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            buttonRow.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    private func imageButton(symbol: String, selector: Selector, tooltip: String) -> NSButton {
        let btn = NSButton()
        btn.target = self
        btn.action = selector
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.toolTip = tooltip
        btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    // MARK: Main pane

    private func buildMainPane() -> NSView {
        let container = NSView()

        // Preview at top.
        previewImageView = NSImageView()
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        previewImageView.layer?.borderWidth = 1
        previewImageView.layer?.cornerRadius = 4
        previewImageView.layer?.magnificationFilter = .nearest
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewImageView)

        let previewCaption = NSTextField(labelWithString: "Live preview · drag screen, click a button card to edit")
        previewCaption.font = NSFont.systemFont(ofSize: 11)
        previewCaption.textColor = .secondaryLabelColor
        previewCaption.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewCaption)

        // Page header: name field + kind popup.
        pageNameField = NSTextField()
        pageNameField.placeholderString = "Page name"
        pageNameField.target = self
        pageNameField.action = #selector(pageNameChanged)
        pageNameField.delegate = self

        pageKindPopup = NSPopUpButton()
        for k in PageKind.allCases {
            pageKindPopup.addItem(withTitle: k.displayName)
            pageKindPopup.lastItem?.representedObject = k
        }
        pageKindPopup.target = self
        pageKindPopup.action = #selector(pageKindChanged)

        let nameLabel = NSTextField(labelWithString: "Name:")
        let kindLabel = NSTextField(labelWithString: "Kind:")
        pageHeaderHost = NSStackView(views: [nameLabel, pageNameField, kindLabel, pageKindPopup])
        pageHeaderHost.orientation = .horizontal
        pageHeaderHost.spacing = 8
        pageHeaderHost.alignment = .firstBaseline
        pageNameField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        pageKindPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        pageHeaderHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pageHeaderHost)

        // Buttons strip — horizontal scroll-friendly stack.
        let stripContainer = NSView()
        stripContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stripContainer)

        let stripLabel = NSTextField(labelWithString: "Buttons")
        stripLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        stripLabel.textColor = .secondaryLabelColor
        stripLabel.translatesAutoresizingMaskIntoConstraints = false
        stripContainer.addSubview(stripLabel)

        buttonStrip = NSStackView()
        buttonStrip.orientation = .horizontal
        buttonStrip.spacing = 10
        buttonStrip.alignment = .centerY
        buttonStrip.translatesAutoresizingMaskIntoConstraints = false
        let stripScroll = NSScrollView()
        stripScroll.hasHorizontalScroller = true
        stripScroll.hasVerticalScroller = false
        stripScroll.borderType = .noBorder
        stripScroll.drawsBackground = false
        stripScroll.documentView = buttonStrip
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        stripContainer.addSubview(stripScroll)

        // Inspector below the strip.
        let inspectorTitle = NSTextField(labelWithString: "Selected Button")
        inspectorTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        inspectorTitle.textColor = .secondaryLabelColor
        inspectorTitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectorTitle)

        inspector = ButtonInspectorView()
        inspector.onChange = { [weak self] updatedButton in
            self?.applyButtonEdit(updatedButton)
        }
        inspector.translatesAutoresizingMaskIntoConstraints = false

        inspectorScroll = NSScrollView()
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.drawsBackground = false
        inspectorScroll.borderType = .noBorder
        inspectorScroll.documentView = inspector
        inspectorScroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectorScroll)

        emptyStateLabel = NSTextField(labelWithString: "Select or add a button to edit it.")
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.font = NSFont.systemFont(ofSize: 12)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyStateLabel)

        // Constraints.
        NSLayoutConstraint.activate([
            // Preview
            previewImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            previewImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 1280),
            previewImageView.heightAnchor.constraint(equalToConstant: 96),

            previewCaption.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 4),
            previewCaption.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            // Page header
            pageHeaderHost.topAnchor.constraint(equalTo: previewCaption.bottomAnchor, constant: 22),
            pageHeaderHost.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            // Button strip
            stripContainer.topAnchor.constraint(equalTo: pageHeaderHost.bottomAnchor, constant: 18),
            stripContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stripContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stripContainer.heightAnchor.constraint(equalToConstant: 130),

            stripLabel.topAnchor.constraint(equalTo: stripContainer.topAnchor),
            stripLabel.leadingAnchor.constraint(equalTo: stripContainer.leadingAnchor),

            stripScroll.topAnchor.constraint(equalTo: stripLabel.bottomAnchor, constant: 6),
            stripScroll.leadingAnchor.constraint(equalTo: stripContainer.leadingAnchor),
            stripScroll.trailingAnchor.constraint(equalTo: stripContainer.trailingAnchor),
            stripScroll.bottomAnchor.constraint(equalTo: stripContainer.bottomAnchor),

            buttonStrip.heightAnchor.constraint(equalToConstant: 100),

            // Inspector
            inspectorTitle.topAnchor.constraint(equalTo: stripContainer.bottomAnchor, constant: 16),
            inspectorTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            inspectorScroll.topAnchor.constraint(equalTo: inspectorTitle.bottomAnchor, constant: 8),
            inspectorScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            inspectorScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            inspectorScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),

            inspector.leadingAnchor.constraint(equalTo: inspectorScroll.contentView.leadingAnchor),
            inspector.topAnchor.constraint(equalTo: inspectorScroll.contentView.topAnchor),
            inspector.widthAnchor.constraint(equalTo: inspectorScroll.widthAnchor, constant: -2),

            emptyStateLabel.centerXAnchor.constraint(equalTo: inspectorScroll.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: inspectorScroll.centerYAnchor),
        ])

        return container
    }

    // MARK: Reload / state

    private var selectedPage: Page? {
        guard let id = selectedPageId else { return nil }
        return store.pages.first { $0.id == id }
    }

    private var selectedButton: PageButton? {
        guard let page = selectedPage, let bid = selectedButtonId else { return nil }
        return page.buttons.first { $0.id == bid }
    }

    private func reloadSidebar() {
        sidebarTable.reloadData()
        if let id = selectedPageId, let row = store.pages.firstIndex(where: { $0.id == id }) {
            sidebarTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    /// Apply the current model state to all editable UI.
    private func applyState() {
        guard let page = selectedPage else {
            pageNameField.stringValue = ""
            pageKindPopup.selectItem(at: 0)
            pageHeaderHost.isHidden = true
            buttonStrip.isHidden = true
            inspector.isHidden = true
            emptyStateLabel.isHidden = true
            return
        }
        pageHeaderHost.isHidden = false
        pageNameField.stringValue = page.name
        if let idx = PageKind.allCases.firstIndex(of: page.kind) {
            pageKindPopup.selectItem(at: idx)
        }

        rebuildButtonStrip()

        if page.kind == .buttonGrid, let btn = selectedButton {
            inspector.isHidden = false
            emptyStateLabel.isHidden = true
            inspector.button = btn
        } else if page.kind == .status {
            inspector.isHidden = true
            emptyStateLabel.isHidden = false
            emptyStateLabel.stringValue =
                "Status pages use the layout / theme / time options in Preferences."
        } else {
            // grid page but nothing selected
            inspector.isHidden = true
            emptyStateLabel.isHidden = false
            emptyStateLabel.stringValue = "Select or add a button to edit it."
        }

        refreshPreview()
    }

    private func rebuildButtonStrip() {
        buttonStrip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let page = selectedPage else { return }
        buttonStrip.isHidden = (page.kind != .buttonGrid)
        guard page.kind == .buttonGrid else { return }

        for (idx, btn) in page.buttons.enumerated() {
            let card = ButtonCardView()
            card.configure(button: btn, palette: settings.theme.palette,
                           selected: btn.id == selectedButtonId, isAddCard: false)
            card.onClick = { [weak self] in self?.selectedButtonId = btn.id }
            card.onMoveLeft = { [weak self] in self?.moveButton(at: idx, by: -1) }
            card.onMoveRight = { [weak self] in self?.moveButton(at: idx, by: +1) }
            card.onDelete = { [weak self] in self?.deleteButton(at: idx) }
            buttonStrip.addArrangedSubview(card)
            card.widthAnchor.constraint(equalToConstant: 96).isActive = true
            card.heightAnchor.constraint(equalToConstant: 96).isActive = true
        }

        if page.buttons.count < 12 {
            let add = ButtonCardView()
            add.configure(button: nil, palette: settings.theme.palette,
                          selected: false, isAddCard: true)
            add.onClick = { [weak self] in self?.addButton() }
            buttonStrip.addArrangedSubview(add)
            add.widthAnchor.constraint(equalToConstant: 96).isActive = true
            add.heightAnchor.constraint(equalToConstant: 96).isActive = true
        }
    }

    private func onSelectionChanged() {
        applyState()
    }

    // MARK: Live preview

    private func startPreviewLoop() {
        previewTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshPreview() }
        RunLoop.main.add(t, forMode: .common)
        previewTimer = t
        refreshPreview()
    }

    private func refreshPreview() {
        guard let page = selectedPage else { return }
        cpu.sample(); memory.sample()
        let palette = settings.theme.palette

        // Reuse the AppDelegate's background cache logic, but inline & best-effort.
        let bg: [UInt8]?
        if let p = settings.backgroundImagePath {
            let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            bg = (try? NexusImage.loadAsFrame(url: url, mode: settings.backgroundScaleMode))
        } else {
            bg = nil
        }

        do {
            let frame: [UInt8]
            switch page.kind {
            case .status:
                let inputs = RenderInputs(date: Date(),
                                          cpuLoad: cpu.usage > 0 ? cpu.usage : 0.42,
                                          memUsage: memory.usage > 0 ? memory.usage : 0.58,
                                          memUsedGB: memory.usedGB,
                                          memTotalGB: memory.totalGB)
                let statusFrame = try LayoutRenderer.render(
                    layout: settings.layout,
                    inputs: inputs,
                    palette: palette,
                    timeFormat: settings.timeFormat,
                    showSeconds: settings.showSeconds,
                    background: bg,
                    backgroundDim: settings.backgroundDim
                )
                frame = try PageRenderer.overlayPageDots(
                    on: statusFrame,
                    palette: palette,
                    pageIndex: store.pages.firstIndex(where: { $0.id == page.id }) ?? 0,
                    pageCount: store.pages.count
                )
            case .buttonGrid:
                frame = try PageRenderer.renderButtonGrid(
                    page: page,
                    palette: palette,
                    background: bg,
                    backgroundDim: settings.backgroundDim,
                    pressedIndex: nil,
                    pageIndex: store.pages.firstIndex(where: { $0.id == page.id }) ?? 0,
                    pageCount: store.pages.count
                )
            }
            if let cg = NexusImage.cgImage(from: frame) {
                previewImageView.image = NSImage(cgImage: cg,
                                                 size: NSSize(width: NexusProtocol.width,
                                                              height: NexusProtocol.height))
            }
        } catch {
            // Preview is best-effort.
        }
    }

    // MARK: Page actions

    @objc private func addPage() {
        let new = Page(name: "Untitled", kind: .buttonGrid, buttons: [])
        store.addPage(new)
        selectedPageId = new.id
        reloadSidebar()
        applyState()
    }

    @objc private func removeSelectedPage() {
        guard let id = selectedPageId, store.pages.count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Remove this page?"
        alert.informativeText = "This can't be undone, but you can recreate it later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let prevIndex = store.pages.firstIndex { $0.id == id } ?? 0
        store.removePage(id: id)
        let next = store.pages.indices.contains(prevIndex)
            ? store.pages[prevIndex]
            : store.pages.last
        selectedPageId = next?.id
        selectedButtonId = nil
        reloadSidebar()
        applyState()
    }

    @objc private func moveSelectedPageUp() {
        guard let id = selectedPageId,
              let idx = store.pages.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        store.movePage(from: idx, to: idx - 1)
        reloadSidebar()
    }

    @objc private func moveSelectedPageDown() {
        guard let id = selectedPageId,
              let idx = store.pages.firstIndex(where: { $0.id == id }),
              idx < store.pages.count - 1 else { return }
        store.movePage(from: idx, to: idx + 1)
        reloadSidebar()
    }

    @objc private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset all pages to defaults?"
        alert.informativeText = "Your current pages will be replaced with Status + Apps + Media."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.resetToDefaults()
        selectedPageId = store.pages.first?.id
        selectedButtonId = nil
        reloadSidebar()
        applyState()
    }

    @objc private func pageNameChanged() {
        guard var page = selectedPage else { return }
        page.name = pageNameField.stringValue
        store.updatePage(page)
        // Reload just the row so the sidebar text updates without losing selection.
        if let row = store.pages.firstIndex(where: { $0.id == page.id }) {
            sidebarTable.reloadData(forRowIndexes: IndexSet(integer: row),
                                    columnIndexes: IndexSet(integer: 0))
        }
    }

    @objc private func pageKindChanged() {
        guard var page = selectedPage,
              let kind = pageKindPopup.selectedItem?.representedObject as? PageKind else { return }
        if page.kind == kind { return }
        page.kind = kind
        if kind == .buttonGrid, page.buttons.isEmpty {
            page.buttons = [PageButton()]
        }
        store.updatePage(page)
        selectedButtonId = page.buttons.first?.id
        applyState()
    }

    @objc private func sidebarSelectionChanged() {
        let row = sidebarTable.selectedRow
        guard row >= 0, row < store.pages.count else { return }
        selectedPageId = store.pages[row].id
        selectedButtonId = store.pages[row].buttons.first?.id
    }

    // MARK: Button actions

    private func addButton() {
        guard var page = selectedPage, page.kind == .buttonGrid else { return }
        let new = PageButton(label: "Btn",
                             icon: .sfSymbol(name: "star.fill"),
                             action: .none)
        page.buttons.append(new)
        store.updatePage(page)
        selectedButtonId = new.id
    }

    private func deleteButton(at index: Int) {
        guard var page = selectedPage,
              page.buttons.indices.contains(index) else { return }
        let removedId = page.buttons[index].id
        page.buttons.remove(at: index)
        store.updatePage(page)
        if selectedButtonId == removedId {
            selectedButtonId = page.buttons.first?.id
        } else {
            applyState()
        }
    }

    private func moveButton(at index: Int, by delta: Int) {
        guard var page = selectedPage,
              page.buttons.indices.contains(index) else { return }
        let target = max(0, min(page.buttons.count - 1, index + delta))
        if target == index { return }
        let b = page.buttons.remove(at: index)
        page.buttons.insert(b, at: target)
        store.updatePage(page)
    }

    private func applyButtonEdit(_ button: PageButton) {
        guard var page = selectedPage,
              let idx = page.buttons.firstIndex(where: { $0.id == button.id }) else { return }
        page.buttons[idx] = button
        store.updatePage(page)
    }

    @objc private func externalPagesChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadSidebar()
            self?.applyState()
        }
    }
}

// MARK: - NSTextField delegate (name field commits on every keystroke)

extension PagesEditorWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSTextField, f === pageNameField {
            pageNameChanged()
        }
    }
}

// MARK: - Sidebar table data source / delegate

extension PagesEditorWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { store.pages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let page = store.pages[row]
        let cell = NSTableCellView()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: page.kind == .status ? "clock" : "square.grid.2x2",
                             accessibilityDescription: nil)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)

        let title = NSTextField(labelWithString: page.name.isEmpty ? "Untitled" : page.name)
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: page.kind == .status
                                   ? "Clock & stats"
                                   : "\(page.buttons.count) button\(page.buttons.count == 1 ? "" : "s")")
        subtitle.font = NSFont.systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(title)
        cell.addSubview(subtitle)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
        ])

        return cell
    }
}
