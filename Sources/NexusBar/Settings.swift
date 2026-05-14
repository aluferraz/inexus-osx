import Foundation

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

    private func broadcast() {
        NotificationCenter.default.post(name: Settings.changed, object: self)
    }
}
