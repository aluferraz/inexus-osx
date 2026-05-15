import Foundation
import NexusCore

/// User-configurable settings persisted in UserDefaults. Observers receive
/// `Settings.changed` notifications whenever any field is mutated.
final class Settings {
    static let shared = Settings()
    static let changed = Notification.Name("NexusBar.settingsChanged")

    enum Layout: String, CaseIterable {
        case clockAndCPU         = "clock+cpu"
        case clockCPUMemory      = "clock+cpu+memory"
        case clockAndDate        = "clock+date"
        case clockOnly           = "clock"
        case cpuAndMemory        = "cpu+memory"

        var displayName: String {
            switch self {
            case .clockAndCPU:     return "Clock + CPU"
            case .clockCPUMemory:  return "Clock + CPU + Memory"
            case .clockAndDate:    return "Date + Clock"
            case .clockOnly:       return "Clock only"
            case .cpuAndMemory:    return "CPU + Memory"
            }
        }
    }

    enum TimeFormat: String, CaseIterable {
        case twentyFour = "24h"
        case twelveHour = "12h"

        var displayName: String { rawValue }
    }

    enum Theme: String, CaseIterable {
        case dark, midnight, sunset, mono, ocean

        var displayName: String {
            switch self {
            case .dark:     return "Dark"
            case .midnight: return "Midnight Blue"
            case .sunset:   return "Sunset"
            case .mono:     return "Monochrome"
            case .ocean:    return "Ocean"
            }
        }
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let layout         = "layout"
        static let timeFormat     = "timeFormat"
        static let showSeconds    = "showSeconds"
        static let theme          = "theme"
        static let brightness     = "brightness"
        static let refreshSeconds = "refreshSeconds"
        static let launchAtLogin  = "launchAtLogin"
        static let bgImagePath    = "backgroundImagePath"
        static let bgScaleMode    = "backgroundScaleMode"
        static let bgDim          = "backgroundDim"
        static let blankOnLock    = "blankOnLock"
    }

    var layout: Layout {
        get { defaults.string(forKey: Key.layout).flatMap(Layout.init(rawValue:)) ?? .clockAndCPU }
        set { defaults.set(newValue.rawValue, forKey: Key.layout); broadcast() }
    }

    var timeFormat: TimeFormat {
        get { defaults.string(forKey: Key.timeFormat).flatMap(TimeFormat.init(rawValue:)) ?? .twentyFour }
        set { defaults.set(newValue.rawValue, forKey: Key.timeFormat); broadcast() }
    }

    var showSeconds: Bool {
        get { defaults.object(forKey: Key.showSeconds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showSeconds); broadcast() }
    }

    var theme: Theme {
        get { defaults.string(forKey: Key.theme).flatMap(Theme.init(rawValue:)) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.theme); broadcast() }
    }

    var brightness: Int {
        get { (defaults.object(forKey: Key.brightness) as? Int) ?? 80 }
        set { defaults.set(max(0, min(100, newValue)), forKey: Key.brightness); broadcast() }
    }

    var refreshSeconds: Double {
        get { (defaults.object(forKey: Key.refreshSeconds) as? Double) ?? 1.0 }
        set { defaults.set(max(0.25, min(10, newValue)), forKey: Key.refreshSeconds); broadcast() }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin); broadcast() }
    }

    var backgroundImagePath: String? {
        get { defaults.string(forKey: Key.bgImagePath) }
        set {
            if let v = newValue, !v.isEmpty { defaults.set(v, forKey: Key.bgImagePath) }
            else { defaults.removeObject(forKey: Key.bgImagePath) }
            broadcast()
        }
    }

    var backgroundScaleMode: NexusImage.ScaleMode {
        get { defaults.string(forKey: Key.bgScaleMode).flatMap(NexusImage.ScaleMode.init(rawValue:)) ?? .fill }
        set { defaults.set(newValue.rawValue, forKey: Key.bgScaleMode); broadcast() }
    }

    /// 0 = no dimming, 100 = fully dimmed to black.
    var backgroundDim: Int {
        get { (defaults.object(forKey: Key.bgDim) as? Int) ?? 25 }
        set { defaults.set(max(0, min(100, newValue)), forKey: Key.bgDim); broadcast() }
    }

    /// Automatically blank the Nexus display when the Mac is locked / its
    /// display sleeps, and restore on unlock / wake. Default on.
    var blankOnLock: Bool {
        get { defaults.object(forKey: Key.blankOnLock) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.blankOnLock); broadcast() }
    }

    private func broadcast() {
        NotificationCenter.default.post(name: Settings.changed, object: self)
    }
}
