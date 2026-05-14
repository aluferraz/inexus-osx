import AppKit

/// Programmatic preferences window. No XIBs, no storyboards. The form is
/// built with NSStackViews; changes flow straight into `Settings.shared`
/// which broadcasts a notification picked up by AppDelegate.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Nexus Bar Preferences"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildContent()
    }

    private let settings = Settings.shared
    private var brightnessSlider: NSSlider!
    private var brightnessLabel: NSTextField!
    private var refreshSlider: NSSlider!
    private var refreshLabel: NSTextField!
    private var loginToggle: NSButton!
    private var loginStatusLabel: NSTextField!

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 14
        form.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        form.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: content.topAnchor),
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            form.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Layout
        form.addArrangedSubview(makeRow(
            label: "Display:",
            control: makePopup(values: Settings.Layout.allCases,
                               selected: settings.layout,
                               titles: { $0.displayName }) { [weak self] new in
                self?.settings.layout = new
            }))

        // Theme
        form.addArrangedSubview(makeRow(
            label: "Theme:",
            control: makePopup(values: Settings.Theme.allCases,
                               selected: settings.theme,
                               titles: { $0.displayName }) { [weak self] new in
                self?.settings.theme = new
            }))

        // Time format
        form.addArrangedSubview(makeRow(
            label: "Time format:",
            control: makePopup(values: Settings.TimeFormat.allCases,
                               selected: settings.timeFormat,
                               titles: { $0.displayName }) { [weak self] new in
                self?.settings.timeFormat = new
            }))

        // Show seconds
        let secondsBox = NSButton(checkboxWithTitle: "Show seconds",
                                  target: self, action: #selector(toggleSeconds(_:)))
        secondsBox.state = settings.showSeconds ? .on : .off
        form.addArrangedSubview(makeRow(label: "", control: secondsBox))

        // Brightness
        brightnessLabel = NSTextField(labelWithString: "\(settings.brightness)%")
        brightnessLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        brightnessSlider = NSSlider(value: Double(settings.brightness), minValue: 0, maxValue: 100,
                                    target: self, action: #selector(brightnessChanged(_:)))
        brightnessSlider.isContinuous = true
        let brightnessRow = NSStackView(views: [brightnessSlider, brightnessLabel])
        brightnessRow.orientation = .horizontal
        brightnessRow.spacing = 10
        brightnessSlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
        brightnessLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        form.addArrangedSubview(makeRow(label: "Brightness:", control: brightnessRow))

        // Refresh rate
        refreshLabel = NSTextField(labelWithString: String(format: "%.1fs", settings.refreshSeconds))
        refreshLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        refreshSlider = NSSlider(value: settings.refreshSeconds, minValue: 0.5, maxValue: 10,
                                 target: self, action: #selector(refreshChanged(_:)))
        refreshSlider.isContinuous = true
        let refreshRow = NSStackView(views: [refreshSlider, refreshLabel])
        refreshRow.orientation = .horizontal
        refreshRow.spacing = 10
        refreshSlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
        refreshLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        form.addArrangedSubview(makeRow(label: "Refresh rate:", control: refreshRow))

        // Login at startup
        loginToggle = NSButton(checkboxWithTitle: "Launch Nexus Bar at login",
                               target: self, action: #selector(toggleLogin(_:)))
        loginToggle.state = settings.launchAtLogin ? .on : .off
        loginToggle.isEnabled = LoginItem.isAppBundled
        form.addArrangedSubview(makeRow(label: "", control: loginToggle))

        loginStatusLabel = NSTextField(labelWithString: LoginItem.statusDescription)
        loginStatusLabel.font = NSFont.systemFont(ofSize: 11)
        loginStatusLabel.textColor = .secondaryLabelColor
        loginStatusLabel.lineBreakMode = .byWordWrapping
        loginStatusLabel.maximumNumberOfLines = 2
        loginStatusLabel.preferredMaxLayoutWidth = 380
        form.addArrangedSubview(loginStatusLabel)
    }

    // MARK: Layout helpers

    private func makeRow(label: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10

        if !label.isEmpty {
            let lbl = NSTextField(labelWithString: label)
            lbl.alignment = .right
            lbl.widthAnchor.constraint(equalToConstant: 100).isActive = true
            row.addArrangedSubview(lbl)
        } else {
            let spacer = NSView()
            spacer.widthAnchor.constraint(equalToConstant: 100).isActive = true
            row.addArrangedSubview(spacer)
        }

        row.addArrangedSubview(control)
        return row
    }

    private func makePopup<T: Hashable & CaseIterable>(
        values: T.AllCases,
        selected: T,
        titles: (T) -> String,
        onChange: @escaping (T) -> Void
    ) -> NSPopUpButton {
        let popup = NSPopUpButton()
        let valuesArray = Array(values)
        for v in valuesArray {
            popup.addItem(withTitle: titles(v))
            if let item = popup.lastItem {
                item.representedObject = v
            }
        }
        if let index = valuesArray.firstIndex(of: selected) {
            popup.selectItem(at: index)
        }
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        objc_setAssociatedObject(popup, &PreferencesWindowController.handlerKey,
                                 onChange as Any, .OBJC_ASSOCIATION_RETAIN)
        return popup
    }

    private static var handlerKey: UInt8 = 0

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject else { return }
        guard let handler = objc_getAssociatedObject(sender,
                                                     &PreferencesWindowController.handlerKey) else { return }

        // Try each concrete type since closures can't be cast generically.
        if let v = value as? Settings.Layout,
           let cb = handler as? (Settings.Layout) -> Void { cb(v); return }
        if let v = value as? Settings.Theme,
           let cb = handler as? (Settings.Theme) -> Void { cb(v); return }
        if let v = value as? Settings.TimeFormat,
           let cb = handler as? (Settings.TimeFormat) -> Void { cb(v); return }
    }

    // MARK: Slider / toggle actions

    @objc private func toggleSeconds(_ sender: NSButton) {
        settings.showSeconds = (sender.state == .on)
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        let v = Int(sender.doubleValue.rounded())
        settings.brightness = v
        brightnessLabel.stringValue = "\(v)%"
    }

    @objc private func refreshChanged(_ sender: NSSlider) {
        let v = (sender.doubleValue * 2).rounded() / 2 // snap to 0.5
        settings.refreshSeconds = v
        refreshLabel.stringValue = String(format: "%.1fs", v)
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        let want = (sender.state == .on)
        settings.launchAtLogin = want
        let ok = LoginItem.set(want)
        loginStatusLabel.stringValue = LoginItem.statusDescription
        if !ok && want { sender.state = .off; settings.launchAtLogin = false }
    }

    // MARK: Show

    func showAndFront() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
    }
}
