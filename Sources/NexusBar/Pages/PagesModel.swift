import Foundation
import CoreGraphics

/// A user-configurable page that appears in the swipe cycle.
struct Page: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: PageKind
    /// Used by `buttonGrid` pages.
    var buttons: [PageButton]
    /// Used by `freeLayout` pages — mix of widgets and buttons at arbitrary positions.
    var elements: [PageElement]

    init(id: UUID = UUID(),
         name: String,
         kind: PageKind,
         buttons: [PageButton] = [],
         elements: [PageElement] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.buttons = buttons
        self.elements = elements
    }

    // Tolerant decode: older saved pages don't have `elements`.
    private enum CodingKeys: String, CodingKey { case id, name, kind, buttons, elements }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.kind = try c.decode(PageKind.self, forKey: .kind)
        self.buttons = try c.decodeIfPresent([PageButton].self, forKey: .buttons) ?? []
        self.elements = try c.decodeIfPresent([PageElement].self, forKey: .elements) ?? []
    }
}

enum PageKind: String, Codable, CaseIterable {
    case status          // global clock/CPU/memory layout, controlled by Settings
    case buttonGrid      // N evenly-spaced tappable buttons
    case freeLayout      // free-positioned mix of widgets and buttons

    var displayName: String {
        switch self {
        case .status:     return "Status (Clock & Stats)"
        case .buttonGrid: return "Button Grid"
        case .freeLayout: return "Free Layout (Mix & Match)"
        }
    }
}

// MARK: - Free-layout elements

/// A Codable CGRect — the device canvas is 640×48 in pixels (top-left origin).
struct PageRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    init(_ r: CGRect) {
        self.init(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct PageElement: Codable, Identifiable, Equatable {
    var id: UUID
    var frame: PageRect
    var kind: ElementKind

    init(id: UUID = UUID(), frame: PageRect, kind: ElementKind) {
        self.id = id
        self.frame = frame
        self.kind = kind
    }
}

/// A free-layout element is either a live data widget or a tappable button.
enum ElementKind: Codable, Equatable {
    case widget(WidgetKind)
    case button(PageButton)

    var typeLabel: String {
        switch self {
        case .widget(let k): return k.displayName
        case .button:        return "Button"
        }
    }
}

/// The live-data widgets available in a free-layout page.
enum WidgetKind: String, Codable, CaseIterable {
    case clock         // current time per Preferences format
    case dateLong      // "Friday 16 May"
    case dateShort     // "FRI 16 MAY"
    case cpuPercent    // "47%"
    case cpuBar        // horizontal load bar
    case ramPercent    // "58%"
    case ramBar        // horizontal load bar
    case ramUsage      // "12.4 / 32 GB"

    var displayName: String {
        switch self {
        case .clock:       return "Clock"
        case .dateLong:    return "Date (long)"
        case .dateShort:   return "Date (short)"
        case .cpuPercent:  return "CPU %"
        case .cpuBar:      return "CPU bar"
        case .ramPercent:  return "RAM %"
        case .ramBar:      return "RAM bar"
        case .ramUsage:    return "RAM used / total"
        }
    }

    /// A sensible default rect for a freshly-inserted widget.
    var defaultRect: PageRect {
        switch self {
        case .clock:       return PageRect(x: 12,  y: 6,  width: 160, height: 36)
        case .dateLong:    return PageRect(x: 12,  y: 28, width: 200, height: 16)
        case .dateShort:   return PageRect(x: 12,  y: 28, width: 110, height: 16)
        case .cpuPercent:  return PageRect(x: 280, y: 14, width: 64,  height: 22)
        case .cpuBar:      return PageRect(x: 280, y: 36, width: 140, height: 8)
        case .ramPercent:  return PageRect(x: 460, y: 14, width: 64,  height: 22)
        case .ramBar:      return PageRect(x: 460, y: 36, width: 140, height: 8)
        case .ramUsage:    return PageRect(x: 460, y: 14, width: 160, height: 14)
        }
    }
}

// MARK: - Buttons (shared between buttonGrid and freeLayout pages)

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
    case animatedFile(path: String)   // GIF / APNG / MP4 / MOV — looping
    case textOnly

    enum Kind: String, CaseIterable {
        case sfSymbol      = "SF Symbol"
        case imageFile     = "Image File"
        case animatedFile  = "Animated (GIF / MP4 / MOV)"
        case textOnly      = "Text Only"
    }

    var kind: Kind {
        switch self {
        case .sfSymbol:      return .sfSymbol
        case .imageFile:     return .imageFile
        case .animatedFile:  return .animatedFile
        case .textOnly:      return .textOnly
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
