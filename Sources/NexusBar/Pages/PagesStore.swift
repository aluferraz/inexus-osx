import Foundation

/// Persists the user's page configuration as JSON inside UserDefaults and
/// broadcasts a `PagesStore.changed` notification whenever pages are mutated.
final class PagesStore {
    static let shared = PagesStore()
    static let changed = Notification.Name("NexusBar.pagesChanged")

    private let key = "pages"
    private let defaults = UserDefaults.standard

    private(set) var pages: [Page] = []

    private init() {
        load()
        if pages.isEmpty {
            pages = PagesStore.defaultPages()
            save(broadcast: false)
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Page].self, from: data) {
            pages = decoded
        }
    }

    private func save(broadcast: Bool = true) {
        if let data = try? JSONEncoder().encode(pages) {
            defaults.set(data, forKey: key)
        }
        if broadcast {
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }

    // MARK: Mutations

    func replaceAll(_ newPages: [Page]) {
        pages = newPages
        save()
    }

    func updatePage(_ page: Page) {
        guard let idx = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[idx] = page
        save()
    }

    func addPage(_ page: Page) {
        pages.append(page)
        save()
    }

    func removePage(id: UUID) {
        pages.removeAll { $0.id == id }
        save()
    }

    func movePage(from: Int, to: Int) {
        guard pages.indices.contains(from), to >= 0, to < pages.count else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: min(to, pages.count))
        save()
    }

    func resetToDefaults() {
        pages = PagesStore.defaultPages()
        save()
    }

    // MARK: First-run defaults

    static func defaultPages() -> [Page] {
        let status = Page(name: "Status", kind: .status, buttons: [])

        let apps = Page(name: "Apps", kind: .buttonGrid, buttons: [
            PageButton(label: "Safari",   icon: .sfSymbol(name: "safari"),
                       action: .launchApp(bundleId: "com.apple.Safari", displayName: "Safari")),
            PageButton(label: "Mail",     icon: .sfSymbol(name: "envelope.fill"),
                       action: .launchApp(bundleId: "com.apple.mail", displayName: "Mail")),
            PageButton(label: "Finder",   icon: .sfSymbol(name: "folder.fill"),
                       action: .launchApp(bundleId: "com.apple.finder", displayName: "Finder")),
            PageButton(label: "Terminal", icon: .sfSymbol(name: "terminal.fill"),
                       action: .launchApp(bundleId: "com.apple.Terminal", displayName: "Terminal")),
            PageButton(label: "Notes",    icon: .sfSymbol(name: "note.text"),
                       action: .launchApp(bundleId: "com.apple.Notes", displayName: "Notes")),
            PageButton(label: "Settings", icon: .sfSymbol(name: "gearshape.fill"),
                       action: .launchApp(bundleId: "com.apple.systempreferences", displayName: "System Settings")),
        ])

        let media = Page(name: "Media", kind: .buttonGrid, buttons: [
            PageButton(label: "Prev", icon: .sfSymbol(name: "backward.fill"),
                       action: .mediaKey(kind: .previous)),
            PageButton(label: "Play", icon: .sfSymbol(name: "playpause.fill"),
                       action: .mediaKey(kind: .playPause)),
            PageButton(label: "Next", icon: .sfSymbol(name: "forward.fill"),
                       action: .mediaKey(kind: .next)),
            PageButton(label: "Vol-", icon: .sfSymbol(name: "speaker.wave.1.fill"),
                       action: .mediaKey(kind: .volumeDown)),
            PageButton(label: "Mute", icon: .sfSymbol(name: "speaker.slash.fill"),
                       action: .mediaKey(kind: .mute)),
            PageButton(label: "Vol+", icon: .sfSymbol(name: "speaker.wave.3.fill"),
                       action: .mediaKey(kind: .volumeUp)),
        ])

        return [status, apps, media]
    }
}
