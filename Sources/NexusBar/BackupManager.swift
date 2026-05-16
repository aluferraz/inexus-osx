import AppKit
import Foundation
import NexusCore

/// Exports and restores the full Nexus Bar configuration as a single zipped
/// bundle (`.nexusbar` extension, which is just a renamed `.zip`).
///
/// Bundle layout:
/// ```
/// MyBackup.nexusbar
/// ├── manifest.json           // pages + settings, with managed-resource paths
/// │                           // rewritten to bare filenames for portability
/// └── resources/
///     ├── <uuid>.gif
///     ├── <uuid>.png
///     └── …                   // every icon/background referenced from the manifest
/// ```
///
/// On import the resources are copied back into the live
/// `~/Library/Application Support/NexusBar/resources/` folder, and paths in
/// the manifest get re-expanded to absolute paths so the renderer finds them.
enum BackupManager {

    static let manifestVersion = 1

    enum BackupError: LocalizedError {
        case zipFailed(String)
        case unzipFailed(String)
        case missingManifest
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let s):      return "Couldn't create zip: \(s)"
            case .unzipFailed(let s):    return "Couldn't extract backup: \(s)"
            case .missingManifest:       return "Backup is missing manifest.json"
            case .decodeFailed(let s):   return "Backup manifest is corrupt: \(s)"
            }
        }
    }

    // MARK: Manifest

    struct Manifest: Codable {
        var version: Int
        var exportedAt: Date
        var pages: [Page]
        var settings: ExportedSettings
    }

    struct ExportedSettings: Codable {
        var layout: String?
        var timeFormat: String?
        var showSeconds: Bool?
        var theme: String?
        var brightness: Int?
        var refreshSeconds: Double?
        var backgroundImagePath: String?       // basename if managed, absolute otherwise
        var backgroundScaleMode: String?
        var backgroundDim: Int?
        var blankOnLock: Bool?
        // launchAtLogin is intentionally excluded — it's a machine-local
        // SMAppService registration that doesn't survive transplant.
    }

    // MARK: Export

    static func export(to destination: URL) throws {
        let tmp = makeTempDir(prefix: "nexusbar-export-")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resourcesOut = tmp.appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesOut,
                                                withIntermediateDirectories: true)

        let livePages = PagesStore.shared.pages

        // Pages rewritten so managed-resource paths become bare filenames.
        let exportPages = livePages.map { rewriteForExport($0) }

        // Build settings snapshot.
        let settingsSnapshot = captureSettings()

        // Collect everything we need to bundle.
        var referencedBasenames = Set<String>()
        for page in livePages {
            for b in page.buttons { collectManagedBasename(b.icon, into: &referencedBasenames) }
            for el in page.elements {
                if case .button(let b) = el.kind {
                    collectManagedBasename(b.icon, into: &referencedBasenames)
                }
            }
        }
        if let bg = Settings.shared.backgroundImagePath, ResourceStore.isManaged(bg) {
            referencedBasenames.insert((bg as NSString).lastPathComponent)
        }

        // Copy each resource into the bundle.
        for basename in referencedBasenames {
            let src = ResourceStore.resourcesDir.appendingPathComponent(basename)
            let dst = resourcesOut.appendingPathComponent(basename)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        // Write manifest.json.
        let manifest = Manifest(version: manifestVersion,
                                exportedAt: Date(),
                                pages: exportPages,
                                settings: settingsSnapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: tmp.appendingPathComponent("manifest.json"))

        // Zip everything up. If destination already exists, remove first —
        // /usr/bin/zip would otherwise append to the existing archive.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try zip(directory: tmp, into: destination)
    }

    // MARK: Import

    static func importFrom(_ source: URL) throws {
        let tmp = makeTempDir(prefix: "nexusbar-import-")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try unzip(source, into: tmp)

        let manifestURL = tmp.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BackupError.missingManifest
        }

        let manifest: Manifest
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(Manifest.self, from: data)
        } catch {
            throw BackupError.decodeFailed(String(describing: error))
        }

        // Copy bundled resources into the live folder. UUID basenames are
        // collision-proof in practice, so skip-on-exists is safe.
        let liveRes = ResourceStore.resourcesDir
        try FileManager.default.createDirectory(at: liveRes,
                                                withIntermediateDirectories: true)
        let bundledRes = tmp.appendingPathComponent("resources")
        if FileManager.default.fileExists(atPath: bundledRes.path),
           let names = try? FileManager.default.contentsOfDirectory(atPath: bundledRes.path) {
            for name in names {
                let src = bundledRes.appendingPathComponent(name)
                let dst = liveRes.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }

        // Apply pages — rewriting bare filenames back to absolute paths.
        let livePages = manifest.pages.map { rewriteForImport($0) }
        PagesStore.shared.replaceAll(livePages)

        // Apply settings.
        applySettings(manifest.settings)

        // Drop the animated-icon cache so re-imported clips re-decode from disk.
        AnimatedIconCache.shared.invalidateAll()
    }

    // MARK: Settings capture / apply

    private static func captureSettings() -> ExportedSettings {
        let s = Settings.shared
        return ExportedSettings(
            layout: s.layout.rawValue,
            timeFormat: s.timeFormat.rawValue,
            showSeconds: s.showSeconds,
            theme: s.theme.rawValue,
            brightness: s.brightness,
            refreshSeconds: s.refreshSeconds,
            backgroundImagePath: s.backgroundImagePath.map {
                ResourceStore.isManaged($0) ? ($0 as NSString).lastPathComponent : $0
            },
            backgroundScaleMode: s.backgroundScaleMode.rawValue,
            backgroundDim: s.backgroundDim,
            blankOnLock: s.blankOnLock
        )
    }

    private static func applySettings(_ e: ExportedSettings) {
        let s = Settings.shared
        if let v = e.layout, let layout = Settings.Layout(rawValue: v) { s.layout = layout }
        if let v = e.timeFormat, let f = Settings.TimeFormat(rawValue: v) { s.timeFormat = f }
        if let v = e.showSeconds { s.showSeconds = v }
        if let v = e.theme, let t = Settings.Theme(rawValue: v) { s.theme = t }
        if let v = e.brightness { s.brightness = v }
        if let v = e.refreshSeconds { s.refreshSeconds = v }
        if let v = e.backgroundScaleMode,
           let mode = NexusImage.ScaleMode(rawValue: v) { s.backgroundScaleMode = mode }
        if let v = e.backgroundDim { s.backgroundDim = v }
        if let v = e.blankOnLock { s.blankOnLock = v }

        if let path = e.backgroundImagePath {
            // Bare filename → expand to live resources dir; full path → keep as-is.
            if path.contains("/") {
                s.backgroundImagePath = path
            } else {
                s.backgroundImagePath = ResourceStore.resourcesDir
                    .appendingPathComponent(path).path
            }
        } else {
            s.backgroundImagePath = nil
        }
    }

    // MARK: Path rewriting

    private static func rewriteForExport(_ page: Page) -> Page {
        var p = page
        p.buttons = p.buttons.map { rewriteButtonForExport($0) }
        p.elements = p.elements.map { el in
            if case .button(let b) = el.kind {
                var copy = el
                copy.kind = .button(rewriteButtonForExport(b))
                return copy
            }
            return el
        }
        return p
    }

    private static func rewriteButtonForExport(_ button: PageButton) -> PageButton {
        var b = button
        b.icon = rewriteIconForExport(b.icon)
        return b
    }

    private static func rewriteIconForExport(_ icon: ButtonIcon) -> ButtonIcon {
        switch icon {
        case .imageFile(let path) where ResourceStore.isManaged(path):
            return .imageFile(path: (path as NSString).lastPathComponent)
        case .animatedFile(let path) where ResourceStore.isManaged(path):
            return .animatedFile(path: (path as NSString).lastPathComponent)
        default:
            return icon
        }
    }

    private static func rewriteForImport(_ page: Page) -> Page {
        var p = page
        p.buttons = p.buttons.map { rewriteButtonForImport($0) }
        p.elements = p.elements.map { el in
            if case .button(let b) = el.kind {
                var copy = el
                copy.kind = .button(rewriteButtonForImport(b))
                return copy
            }
            return el
        }
        return p
    }

    private static func rewriteButtonForImport(_ button: PageButton) -> PageButton {
        var b = button
        b.icon = rewriteIconForImport(b.icon)
        return b
    }

    private static func rewriteIconForImport(_ icon: ButtonIcon) -> ButtonIcon {
        switch icon {
        case .imageFile(let path) where !path.contains("/"):
            return .imageFile(path: liveResourcePath(for: path))
        case .animatedFile(let path) where !path.contains("/"):
            return .animatedFile(path: liveResourcePath(for: path))
        default:
            return icon
        }
    }

    private static func liveResourcePath(for basename: String) -> String {
        ResourceStore.resourcesDir.appendingPathComponent(basename).path
    }

    private static func collectManagedBasename(_ icon: ButtonIcon, into set: inout Set<String>) {
        switch icon {
        case .imageFile(let path), .animatedFile(let path):
            if ResourceStore.isManaged(path) {
                set.insert((path as NSString).lastPathComponent)
            }
        default: break
        }
    }

    // MARK: Shell helpers (zip / unzip via the system binaries — already on every Mac)

    private static func zip(directory: URL, into output: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-rq", output.path, "manifest.json", "resources"]
        proc.currentDirectoryURL = directory
        let err = Pipe(); proc.standardError = err
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = (try? err.fileHandleForReading.readToEnd()).flatMap {
                String(data: $0, encoding: .utf8)
            } ?? "zip exited \(proc.terminationStatus)"
            throw BackupError.zipFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func unzip(_ archive: URL, into directory: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-qo", archive.path, "-d", directory.path]
        let err = Pipe(); proc.standardError = err
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = (try? err.fileHandleForReading.readToEnd()).flatMap {
                String(data: $0, encoding: .utf8)
            } ?? "unzip exited \(proc.terminationStatus)"
            throw BackupError.unzipFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func makeTempDir(prefix: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
