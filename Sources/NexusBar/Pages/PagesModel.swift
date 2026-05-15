import Foundation

/// A user-configurable page that appears in the swipe cycle.
struct Page: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: PageKind
    var buttons: [PageButton]

    init(id: UUID = UUID(), name: String, kind: PageKind, buttons: [PageButton] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.buttons = buttons
    }
}

enum PageKind: String, Codable, CaseIterable {
    case status          // global clock/CPU/memory layout, controlled by Settings
    case buttonGrid      // N tappable buttons

    var displayName: String {
        switch self {
        case .status:     return "Status (Clock & Stats)"
        case .buttonGrid: return "Button Grid"
        }
    }
}

struct PageButton: Codable, Identifiable, Equatable {
    var id: UUID
    var label: String
    var icon: ButtonIcon
    var action: ButtonAction

    init(id: UUID = UUID(),
         label: String = "",
         icon: ButtonIcon = .sfSymbol(name: "square"),
         action: ButtonAction = .none) {
        self.id = id
        self.label = label
        self.icon = icon
        self.action = action
    }
}

enum ButtonIcon: Codable, Equatable {
    case sfSymbol(name: String)
    case imageFile(path: String)
    case textOnly

    enum Kind: String, CaseIterable {
        case sfSymbol = "SF Symbol"
        case imageFile = "Image File"
        case textOnly = "Text Only"
    }

    var kind: Kind {
        switch self {
        case .sfSymbol: return .sfSymbol
        case .imageFile: return .imageFile
        case .textOnly: return .textOnly
        }
    }
}

enum ButtonAction: Codable, Equatable {
    case none
    case launchApp(bundleId: String, displayName: String)
    case openURL(url: String)
    case runShortcut(name: String)
    case runScript(path: String, args: [String])
    case sendKeystroke(keyCode: UInt16, modifiers: UInt64, label: String)
    case mediaKey(kind: MediaKey)
    case nextPage
    case previousPage

    enum Kind: String, CaseIterable {
        case none           = "Do nothing"
        case launchApp      = "Launch App"
        case openURL        = "Open URL"
        case runShortcut    = "Run macOS Shortcut"
        case runScript      = "Run Script"
        case sendKeystroke  = "Send Keystroke"
        case mediaKey       = "Media Key"
        case nextPage       = "Next Page"
        case previousPage   = "Previous Page"
    }

    var kind: Kind {
        switch self {
        case .none:           return .none
        case .launchApp:      return .launchApp
        case .openURL:        return .openURL
        case .runShortcut:    return .runShortcut
        case .runScript:      return .runScript
        case .sendKeystroke:  return .sendKeystroke
        case .mediaKey:       return .mediaKey
        case .nextPage:       return .nextPage
        case .previousPage:   return .previousPage
        }
    }

    /// A blank instance for a chosen kind, used when the user switches action
    /// type in the editor and we need a sensible default for the new variant.
    static func empty(for kind: Kind) -> ButtonAction {
        switch kind {
        case .none:           return .none
        case .launchApp:      return .launchApp(bundleId: "", displayName: "")
        case .openURL:        return .openURL(url: "https://")
        case .runShortcut:    return .runShortcut(name: "")
        case .runScript:      return .runScript(path: "", args: [])
        case .sendKeystroke:  return .sendKeystroke(keyCode: 0, modifiers: 0, label: "")
        case .mediaKey:       return .mediaKey(kind: .playPause)
        case .nextPage:       return .nextPage
        case .previousPage:   return .previousPage
        }
    }

    var summary: String {
        switch self {
        case .none:                            return "Do nothing"
        case .launchApp(_, let name):          return name.isEmpty ? "Launch app…" : "Launch \(name)"
        case .openURL(let url):                return url.isEmpty ? "Open URL…" : "Open \(url)"
        case .runShortcut(let name):           return name.isEmpty ? "Run Shortcut…" : "Run \"\(name)\""
        case .runScript(let path, _):          return path.isEmpty ? "Run script…" : "Run \((path as NSString).lastPathComponent)"
        case .sendKeystroke(_, _, let label):  return label.isEmpty ? "Send keystroke…" : "Send \(label)"
        case .mediaKey(let kind):              return kind.displayName
        case .nextPage:                        return "Next page"
        case .previousPage:                    return "Previous page"
        }
    }
}

enum MediaKey: String, Codable, CaseIterable {
    case playPause   = "playPause"
    case next        = "next"
    case previous    = "previous"
    case volumeUp    = "volumeUp"
    case volumeDown  = "volumeDown"
    case mute        = "mute"

    var displayName: String {
        switch self {
        case .playPause:   return "Play / Pause"
        case .next:        return "Next Track"
        case .previous:    return "Previous Track"
        case .volumeUp:    return "Volume Up"
        case .volumeDown:  return "Volume Down"
        case .mute:        return "Mute"
        }
    }

    /// IOKit `NX_KEYTYPE_…` constants used to construct system-defined NSEvents.
    var keyCode: Int32 {
        switch self {
        case .playPause:   return 16
        case .next:        return 17
        case .previous:    return 18
        case .volumeUp:    return 0
        case .volumeDown:  return 1
        case .mute:        return 7
        }
    }
}
