import AppKit
import NexusCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    // UI
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var prefsController: PreferencesWindowController?

    // Device + monitors
    private var device: NexusDevice?
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let recognizer = NexusGestureRecognizer()
    private let settings = Settings.shared

    // Rendering — runs on a dedicated background queue so slow HID writes
    // never block the menu / status item from staying responsive.
    private let renderQueue = DispatchQueue(label: "com.nexusbar.render", qos: .userInitiated)
    private var renderTimer: DispatchSourceTimer?
    private var blanked = false
    private var showingCustomImage = false

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

        let image = NSMenuItem(title: "Push Image…",
                               action: #selector(pushImage),
                               keyEquivalent: "o")
        image.target = self
        menu.addItem(image)

        let restore = NSMenuItem(title: "Restore Live Display",
                                 action: #selector(restoreLive),
                                 keyEquivalent: "r")
        restore.target = self
        menu.addItem(restore)

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
        guard !showingCustomImage, !blanked else { return }

        renderQueue.async { [weak self] in self?.cpu.sample(); self?.memory.sample() }

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
        guard let device, !blanked, !showingCustomImage else { return }
        cpu.sample()
        memory.sample()

        let inputs = RenderInputs(date: Date(),
                                  cpuLoad: cpu.usage,
                                  memUsage: memory.usage,
                                  memUsedGB: memory.usedGB,
                                  memTotalGB: memory.totalGB)
        do {
            let frame = try LayoutRenderer.render(
                layout: settings.layout,
                inputs: inputs,
                palette: settings.theme.palette,
                timeFormat: settings.timeFormat,
                showSeconds: settings.showSeconds
            )
            try device.showFrame(frame)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.statusMenuItem.title = "Render error: \(error)"
            }
        }
    }

    // MARK: - Settings observation

    @objc private func settingsDidChange() {
        renderQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            try? device.setBrightness(self.settings.brightness)
        }
        // Restart the timer with the (possibly new) interval and avoid a stale
        // frame lingering during the gap.
        startRenderLoop()
        renderQueue.async { [weak self] in self?.renderTick() }
    }

    // MARK: - Menu actions

    @objc private func openPreferences() {
        if prefsController == nil { prefsController = PreferencesWindowController() }
        prefsController?.showAndFront()
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

    @objc private func pushImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.message = "Pick a 640×48 image (other sizes will be stretched)."
        guard panel.runModal() == .OK, let url = panel.url, let device else { return }
        do {
            let frame = try NexusImage.loadAsFrame(url: url)
            showingCustomImage = true
            stopRenderLoop()
            renderQueue.async { try? device.showFrame(frame) }
            statusMenuItem.title = "Showing \(url.lastPathComponent)"
        } catch {
            statusMenuItem.title = "Image error: \(error)"
        }
    }

    @objc private func restoreLive() {
        showingCustomImage = false
        startRenderLoop()
    }

    @objc private func reconnectDevice() {
        stopRenderLoop()
        device?.close()
        device = nil
        blanked = false
        showingCustomImage = false
        statusMenuItem.title = "Reconnecting…"
        connectAndStart()
    }

    // MARK: - Touch

    private func handleTouch(_ event: NexusTouchEvent) {
        guard let gesture = recognizer.feed(event) else { return }
        switch gesture {
        case .tap(let x):
            if x < NexusProtocol.width / 2 {
                toggleBlank()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.statusItem.button?.performClick(nil)
                }
            }
        case .swipeLeft:
            settings.brightness = max(0, settings.brightness - 20)
        case .swipeRight:
            settings.brightness = min(100, settings.brightness + 20)
        case .jitter, .timeout:
            break
        }
    }
}
