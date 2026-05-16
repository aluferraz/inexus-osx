import AppKit
import Foundation

/// Imports an animated-icon clip into the resources folder, transcoding
/// WebM → MP4 via `ffmpeg` along the way because macOS doesn't ship a WebM
/// decoder in AVFoundation or ImageIO.
enum ClipImporter {

    enum ImportError: Error {
        /// The source was a .webm and `ffmpeg` wasn't found on $PATH.
        case webmNeedsFfmpeg
        /// `ffmpeg` ran but exited non-zero.
        case ffmpegFailed(stderr: String)
        /// `FileManager` copy / transcode write failed.
        case copyFailed(underlying: Error)
    }

    /// Copy / transcode `url` into the managed resources folder and return
    /// the stable absolute path the model should store.
    static func adopt(_ url: URL) -> Result<String, ImportError> {
        let ext = url.pathExtension.lowercased()
        if ext == "webm" {
            return transcodeWebM(url)
        }
        return .success(ResourceStore.adopt(url))
    }

    /// Resolve ffmpeg by checking the usual Homebrew + system locations.
    /// Returns nil if it isn't installed.
    static var ffmpegPath: String? {
        for p in ["/opt/homebrew/bin/ffmpeg",
                  "/usr/local/bin/ffmpeg",
                  "/opt/local/bin/ffmpeg",
                  "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // MARK: WebM transcoding

    private static func transcodeWebM(_ url: URL) -> Result<String, ImportError> {
        guard let ffmpeg = ffmpegPath else { return .failure(.webmNeedsFfmpeg) }

        let resources = ResourceStore.resourcesDir
        do {
            try FileManager.default.createDirectory(at: resources,
                                                    withIntermediateDirectories: true)
        } catch {
            return .failure(.copyFailed(underlying: error))
        }
        // Output as GIF — much smaller in RAM than a video stream once decoded,
        // and ImageIO reads it as cheap per-frame CGImages. 12 fps × 128 px is
        // plenty for an icon-sized loop.
        let dest = resources.appendingPathComponent(UUID().uuidString + ".gif")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = [
            "-y",
            "-loglevel", "error",
            "-i", url.path,
            // Two-pass palette generation inside one filter graph — yields a
            // ~10× smaller file than naïve "scale to GIF" at the same quality.
            "-vf", "fps=12,scale=128:-1:flags=lanczos,split[s0][s1];" +
                   "[s0]palettegen=max_colors=128[p];" +
                   "[s1][p]paletteuse=dither=bayer:bayer_scale=5",
            "-loop", "0",
            dest.path,
        ]
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()

        do {
            try proc.run()
        } catch {
            return .failure(.copyFailed(underlying: error))
        }
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8) ?? "ffmpeg exited \(proc.terminationStatus)"
            return .failure(.ffmpegFailed(stderr: s.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(dest.path)
    }
}
