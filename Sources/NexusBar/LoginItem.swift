import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for managing launch-at-login.
/// Only effective when running from an installed .app bundle.
enum LoginItem {

    /// True if the running process is inside an .app bundle (a precondition
    /// for SMAppService to function).
    static var isAppBundled: Bool {
        Bundle.main.bundleIdentifier != nil &&
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Current status string, suitable for surfacing in the UI.
    static var statusDescription: String {
        guard isAppBundled else {
            return "Install NexusBar.app to /Applications to use launch at login."
        }
        switch SMAppService.mainApp.status {
        case .enabled:        return "Will launch at login."
        case .requiresApproval:
            return "Approval required in System Settings → Login Items."
        case .notRegistered:  return "Not set to launch at login."
        case .notFound:       return "App service entry not found."
        @unknown default:     return "Unknown state."
        }
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isAppBundled else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("LoginItem.set(\(enabled)) failed: \(error)")
            return false
        }
    }

    /// Reconcile the actual login-item state with the value stored in Settings.
    static func sync(with stored: Bool) {
        guard isAppBundled else { return }
        let status = SMAppService.mainApp.status
        let actuallyEnabled = (status == .enabled || status == .requiresApproval)
        if stored != actuallyEnabled {
            set(stored)
        }
    }
}
