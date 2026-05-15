import AppKit
import NexusCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    // UI
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var prefsController: PreferencesWindowController?
    private var backgroundController: BackgroundWindowController?
    private var pagesEditorController: PagesEditorWindowController?

    // Device + monitors
    private var device: NexusDevice?
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let recognizer = NexusGestureRecognizer()
    private let settings = Settings.shared
    private let pagesStore = PagesStore.shared
    private let executor = ActionExecutor()

    // Rendering — runs on a dedicated background queue so slow HID writes
    // never block the menu / status item from staying responsive.
    private let renderQueue = DispatchQueue(label: "com.nexusbar.render", qos: .userInitiated)
    private var renderTimer: DispatchSourceTimer?
    private var blanked = false
    private var cachedBackground: [UInt8]?
    private var cachedBackgroundKey: String = ""
    private var currentPageIndex: Int = 0
    private var pressedButtonIndex: Int?
    private var pressFlashUntil: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled",
                                   accessibilityDescription: "Nexus Bar")
            button.image?.isTemplate = true
        }
        buildMenu()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsDidChange),
                                               name: Settings.changed,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(pagesDidChange),
                                               name: PagesStore.changed,
                                               object: nil)

        executor.onNavigation = { [weak self] dir in
            guard let self else { return }
            switch dir {
            case .next:     self.gotoPage(self.currentPageIndex + 1)
            case .previous: self.gotoPage(self.currentPageIndex - 1)
            }
        }

        LoginItem.sync(with: settings.launchAtLogin)
        connectAndStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRenderLoop()
        device?.close()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        statusMenuItem = NSMenuItem(title: "Searching for iCUE Nexus…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let pagesItem = NSMenuItem(title: "Edit Pages…",
                                   action: #selector(openPagesEditor),
                                   keyEquivalent: "e")
        pagesItem.target = self
        menu.addItem(pagesItem)

        let bgItem = NSMenuItem(title: "Background Image…",
                                action: #selector(openBackgroundWindow),
                                keyEquivalent: "i")
        bgItem.target = self
        menu.addItem(bgItem)

        let prefsItem = NSMenuItem(title: "Preferences…",
                                   action: #selector(openPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let blank = NSMenuItem(title: "Blank Screen",
                               action: #selector(toggleBlank),
                               keyEquivalent: "b")
        blank.target = self
        menu.addItem(blank)

        menu.addItem(.separator())

        let reconnect = NSMenuItem(title: "Reconnect Device",
                                   action: #selector(reconnectDevice),
                                   keyEquivalent: "")
        reconnect.target = self
        menu.addItem(reconnect)

        menu.addItem(NSMenuItem(title: "Quit Nexus Bar",
                                action: #selector(NSApp.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Device lifecycle

    private func connectAndStart() {
        do {
            let dev = try NexusDevice.open()
            device = dev
            dev.scheduleOnRunLoop()
            dev.onTouch { [weak self] event in self?.handleTouch(event) }
            let fw = (try? dev.firmwareVersion()) ?? "?"
            try dev.setBrightness(settings.brightness)
            DispatchQueue.main.async { [weak self] in
                self?.statusMenuItem.title = "Connected — firmware \(fw)"
            }
            startRenderLoop()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.statusMenuItem.title = "Disconnected — \(error)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.connectAndStart()
            }
        }
    }

    // MARK: - Render loop (background queue)

    private func startRenderLoop() {
        stopRenderLoop()
        guard !blanked else { return }

        renderQueue.async { [weak self] in
            self?.cpu.sample()
            self?.memory.sample()
            self?.refreshBackgroundCacheIfNeeded()
        }

        let timer = DispatchSource.makeTimerSource(queue: renderQueue)
        let interval = max(0.25, settings.refreshSeconds)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.renderTick() }
        renderTimer = timer
        timer.resume()
    }

    private func stopRenderLoop() {
        renderTimer?.cancel()
        renderTimer = nil
    }

    private func renderTick() {
        guard let device, !blanked else { return }
        cpu.sample()
        memory.sample()
        refreshBackgroundCacheIfNeeded()

        // Clear the press highlight after a short flash.
        if pressedButtonIndex != nil, Date() > pressFlashUntil {
            pressedButtonIndex = nil
        }

        let pages = pagesStore.pages
        guard !pages.isEmpty else {
            renderEmptyState(device: device)
            return
        }

        let pageIndex = clampedPageIndex
        let page = pages[pageIndex]
        let palette = settings.theme.palette

        do {
            let frame: [UInt8]
            switch page.kind {
            case .status:
                let inputs = RenderInputs(date: Date(),
                                          cpuLoad: cpu.usage,
                                          memUsage: memory.usage,
                                          memUsedGB: memory.usedGB,
                                          memTotalGB: memory.totalGB)
                let statusFrame = try LayoutRenderer.render(
                    layout: settings.layout,
                    inputs: inputs,
                    palette: palette,
                    timeFormat: settings.timeFormat,
                    showSeconds: settings.showSeconds,
                    background: cachedBackground,
                    backgroundDim: settings.backgroundDim
                )
                frame = try PageRenderer.overlayPageDots(
                    on: statusFrame,
                    palette: palette,
                    pageIndex: pageIndex,
                    pageCount: pages.count
                )
            case .buttonGrid:
                frame = try PageRenderer.renderButtonGrid(
                    page: page,
                    palette: palette,
                    background: cachedBackground,
                    backgroundDim: settings.backgroundDim,
                    pressedIndex: pressedButtonIndex,
                    pageIndex: pageIndex,
                    pageCount: pages.count
                )
            }
            try device.showFrame(frame)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.statusMenuItem.title = "Render error: \(error)"
            }
        }
    }

    private func renderEmptyState(device: NexusDevice) {
        let palette = settings.theme.palette
        do {
            let frame = try NexusImage.renderToFrame { ctx in
                ctx.setFillColor(palette.background.cgColor)
                ctx.fill(CGRect(x: 0, y: 0,
                                width: NexusProtocol.width,
                                height: NexusProtocol.height))
                let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ns
                defer { NSGraphicsContext.restoreGraphicsState() }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: palette.secondary,
                ]
                let s = "No pages configured — open Edit Pages…"
                let size = (s as NSString).size(withAttributes: attrs)
                (s as NSString).draw(at: NSPoint(x: (640 - size.width) / 2,
                                                 y: (48 - size.height) / 2),
                                     withAttributes: attrs)
            }
            try device.showFrame(frame)
        } catch {}
    }

    /// Reload + rasterize the background image when its path or scale mode
    /// changes. Runs on `renderQueue` (or `settingsDidChange`).
    private func refreshBackgroundCacheIfNeeded() {
        let path = settings.backgroundImagePath ?? ""
        let mode = settings.backgroundScaleMode.rawValue
        let key = "\(path)|\(mode)"
        if key == cachedBackgroundKey { return }
        cachedBackgroundKey = key

        guard !path.isEmpty else {
            cachedBackground = nil
            return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            cachedBackground = try NexusImage.loadAsFrame(url: url, mode: settings.backgroundScaleMode)
        } catch {
            cachedBackground = nil
            DispatchQueue.main.async { [weak self] in
                self?.statusMenuItem.title = "Background error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Page navigation

    private var clampedPageIndex: Int {
        let count = pagesStore.pages.count
        guard count > 0 else { return 0 }
        return ((currentPageIndex % count) + count) % count
    }

    private func gotoPage(_ index: Int) {
        let count = pagesStore.pages.count
        guard count > 0 else { return }
        currentPageIndex = ((index % count) + count) % count
        renderQueue.async { [weak self] in self?.renderTick() }
    }

    // MARK: - Observers

    @objc private func settingsDidChange() {
        renderQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            try? device.setBrightness(self.settings.brightness)
        }
        startRenderLoop()
        renderQueue.async { [weak self] in self?.renderTick() }
    }

    @objc private func pagesDidChange() {
        renderQueue.async { [weak self] in self?.renderTick() }
    }

    // MARK: - Menu actions

    @objc private func openPreferences() {
        if prefsController == nil { prefsController = PreferencesWindowController() }
        prefsController?.showAndFront()
    }

    @objc private func openPagesEditor() {
        if pagesEditorController == nil { pagesEditorController = PagesEditorWindowController() }
        pagesEditorController?.showAndFront()
    }

    @objc private func openBackgroundWindow() {
        if backgroundController == nil { backgroundController = BackgroundWindowController() }
        backgroundController?.showAndFront()
    }

    @objc private func toggleBlank() {
        guard let device else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            do {
                if self.blanked {
                    self.blanked = false
                    try device.setBrightness(self.settings.brightness)
                    DispatchQueue.main.async { self.startRenderLoop() }
                } else {
                    self.blanked = true
                    self.stopRenderLoop()
                    try device.blankScreen()
                }
            } catch {
                DispatchQueue.main.async { self.statusMenuItem.title = "Blank error: \(error)" }
            }
        }
    }

    @objc private func reconnectDevice() {
        stopRenderLoop()
        device?.close()
        device = nil
        blanked = false
        statusMenuItem.title = "Reconnecting…"
        connectAndStart()
    }

    // MARK: - Touch

    private func handleTouch(_ event: NexusTouchEvent) {
        guard let gesture = recognizer.feed(event) else { return }

        switch gesture {
        case .swipeLeft:
            gotoPage(currentPageIndex - 1)
        case .swipeRight:
            gotoPage(currentPageIndex + 1)
        case .tap(let x):
            handleTap(x: x)
        case .jitter, .timeout:
            break
        }
    }

    private func handleTap(x: Int) {
        let pages = pagesStore.pages
        guard !pages.isEmpty else { return }
        let page = pages[clampedPageIndex]

        switch page.kind {
        case .status:
            // Same shortcuts as before: left half blanks, right half opens the menu.
            if x < NexusProtocol.width / 2 {
                toggleBlank()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.statusItem.button?.performClick(nil)
                }
            }
        case .buttonGrid:
            guard !page.buttons.isEmpty else { return }
            let n = page.buttons.count
            let cellWidth = NexusProtocol.width / n
            let idx = min(n - 1, max(0, x / max(1, cellWidth)))
            pressedButtonIndex = idx
            pressFlashUntil = Date().addingTimeInterval(0.25)
            renderQueue.async { [weak self] in self?.renderTick() }
            executor.execute(page.buttons[idx].action)
        }
    }
}
