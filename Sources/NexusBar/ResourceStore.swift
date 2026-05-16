import AppKit
import Foundation

/// Copies user-picked icon / background files into a stable location inside
/// the app's Application Support folder so moves or deletes of the source
/// don't break their button icon or background image.
///
/// Files end up at `~/Library/Application Support/NexusBar/resources/<uuid>.<ext>`.
/// We never rewrite or delete here — if the user picks a new icon, the previous
/// copy stays on disk (orphaned, ~few KB). They can clear the folder by hand if
/// they want it back.
enum ResourceStore {

    /// Copy `url` into our managed folder and return the absolute path of the
    /// new copy. On error (no disk space, permissions, etc.), fall back to the
    /// original path — better than losing the user's selection.
    static func adopt(_ url: URL) -> String {
        do {
            try ensureDir()
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let dest = resourcesDir.appendingPathComponent(UUID().uuidString + ext)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest.path
        } catch {
            return url.path
        }
    }

    /// True when `path` lives inside our managed resources folder.
    static func isManaged(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.hasPrefix(resourcesDir.path + "/")
    }

    static var resourcesDir: URL {
        appSupportDir.appendingPathComponent("resources", isDirectory: true)
    }

    // MARK: Internals

    private static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NexusBar", isDirectory: true)
    }

    private static func ensureDir() throws {
        let dir = resourcesDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir,
                                                    withIntermediateDirectories: true)
        }
    }
}
