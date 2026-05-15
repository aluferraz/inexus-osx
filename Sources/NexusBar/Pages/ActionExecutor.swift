import Foundation
import AppKit
import Carbon.HIToolbox

/// Fires off the side-effect for a `ButtonAction`. Page-nav actions are
/// reported via a delegate callback so the AppDelegate can flip pages.
final class ActionExecutor {

    /// Called for navigation actions; the rest are handled internally.
    var onNavigation: ((NavigationDirection) -> Void)?

    enum NavigationDirection { case next, previous }

    func execute(_ action: ButtonAction) {
        switch action {
        case .none:
            break
        case .launchApp(let bundleId, _):
            launchApp(bundleId: bundleId)
        case .openURL(let urlString):
            openURL(urlString)
        case .runShortcut(let name):
            runShortcut(name)
        case .runScript(let path, let args):
            runScript(path: path, args: args)
        case .sendKeystroke(let keyCode, let modifiers, _):
            sendKeystroke(keyCode: keyCode, modifiers: modifiers)
        case .mediaKey(let kind):
            postMediaKey(kind.keyCode)
        case .nextPage:
            onNavigation?(.next)
        case .previousPage:
            onNavigation?(.previous)
        }
    }

    // MARK: Apps + URLs

    private func launchApp(bundleId: String) {
        guard !bundleId.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSLog("Unknown app bundle id: \(bundleId)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("Launch \(bundleId) failed: \(error)") }
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Scripts

    private func runShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        runShell("/usr/bin/shortcuts", args: ["run", name])
    }

    private func runScript(path: String, args: [String]) {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return }
        runShell(expanded, args: args)
    }

    private func runShell(_ executable: String, args: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            do { try p.run() } catch {
                NSLog("Run \(executable) failed: \(error)")
            }
        }
    }

    // MARK: Keystrokes (CGEvent — requires Accessibility on first use)

    private func sendKeystroke(keyCode: UInt16, modifiers: UInt64) {
        let src = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: modifiers)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: Media keys (NSEvent.systemDefined — no Accessibility needed)

    private func postMediaKey(_ keyType: Int32) {
        func post(_ down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (Int(keyType) << 16) | (down ? (0xA << 8) : (0xB << 8))
            guard let ev = NSEvent.otherEvent(with: .systemDefined,
                                              location: .zero,
                                              modifierFlags: flags,
                                              timestamp: 0,
                                              windowNumber: 0,
                                              context: nil,
                                              subtype: 8,
                                              data1: data1,
                                              data2: -1) else { return }
            ev.cgEvent?.post(tap: .cghidEventTap)
        }
        post(true)
        post(false)
    }
}
