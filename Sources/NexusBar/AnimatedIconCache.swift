import AppKit
import AVFoundation
import CoreGraphics
import ImageIO

/// One pre-decoded animated icon — frames + per-frame durations, kept in RAM.
/// Frames are downsampled to at most `maxFrameDimension` pixels on the longest
/// edge at load time; the device panel is 48 px tall so anything bigger just
/// burns RAM and decode time.
private let maxFrameDimension: CGFloat = 128

final class AnimatedIcon {
    let frames: [CGImage]
    let durations: [TimeInterval]
    let totalDuration: TimeInterval

    init(frames: [CGImage], durations: [TimeInterval]) {
        precondition(frames.count == durations.count)
        self.frames = frames
        self.durations = durations
        self.totalDuration = max(0.001, durations.reduce(0, +))
    }

    /// Return the frame to display at `time` seconds since some epoch
    /// (we mod by totalDuration internally so the source epoch doesn't matter).
    func frame(at time: TimeInterval) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }
        let t = totalDuration > 0
            ? (time.truncatingRemainder(dividingBy: totalDuration) + totalDuration)
                .truncatingRemainder(dividingBy: totalDuration)
            : 0
        var acc: TimeInterval = 0
        for (i, d) in durations.enumerated() {
            acc += d
            if t < acc { return frames[i] }
        }
        return frames.last
    }
}

/// Decodes and caches animated icons by absolute path. Designed for small,
/// short loops on the order of <2 MB — there's no eviction.
final class AnimatedIconCache {
    static let shared = AnimatedIconCache()

    private var cache: [String: AnimatedIcon] = [:]
    private let queue = DispatchQueue(label: "com.nexusbar.animcache",
                                      attributes: .concurrent)

    /// Synchronous load. First call for a given path decodes; subsequent calls
    /// return the cached `AnimatedIcon`. Returns nil if the file is missing or
    /// the codec is unsupported (e.g. WebM — convert to MP4 first).
    func load(path: String) -> AnimatedIcon? {
        let expanded = (path as NSString).expandingTildeInPath
        if let hit = queue.sync(execute: { cache[expanded] }) { return hit }
        guard let icon = decode(path: expanded) else { return nil }
        queue.async(flags: .barrier) { self.cache[expanded] = icon }
        return icon
    }

    /// Drop a single cached icon — call when the user picks a new file for a
    /// button so the next render re-reads from disk.
    func invalidate(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        queue.async(flags: .barrier) { self.cache.removeValue(forKey: expanded) }
    }

    func invalidateAll() {
        queue.async(flags: .barrier) { self.cache.removeAll() }
    }

    // MARK: Decode dispatch

    private func decode(path: String) -> AnimatedIcon? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v", "mov":
            return decodeVideo(url: URL(fileURLWithPath: path))
        default:
            // GIF / APNG / HEIC / animated WebP all go through CGImageSource.
            // For static images (single frame), we still return a 1-frame
            // AnimatedIcon so the renderer doesn't need a special path.
            return decodeViaImageIO(url: URL(fileURLWithPath: path))
        }
    }

    // MARK: ImageIO (GIF / APNG / animated HEIC)

    private func decodeViaImageIO(url: URL) -> AnimatedIcon? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }

        // Thumbnail-decode so frames are pre-shrunk in RAM instead of being
        // full-resolution CGImages that we'd downscale on every render.
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceThumbnailMaxPixelSize:          maxFrameDimension,
            kCGImageSourceShouldCacheImmediately:         true,
        ]

        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary)
                          ?? CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(cg)
            durations.append(frameDuration(source: src, index: i))
        }
        guard !frames.isEmpty else { return nil }
        return AnimatedIcon(frames: frames, durations: durations)
    }

    private func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        let fallback: TimeInterval = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any] else { return fallback }

        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let d = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, d > 0 { return d }
            if let d = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval, d > 0 { return d }
        }
        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let d = png[kCGImagePropertyAPNGUnclampedDelayTime] as? TimeInterval, d > 0 { return d }
            if let d = png[kCGImagePropertyAPNGDelayTime] as? TimeInterval, d > 0 { return d }
        }
        if let heics = props[kCGImagePropertyHEICSDictionary] as? [CFString: Any] {
            if let d = heics[kCGImagePropertyHEICSUnclampedDelayTime] as? TimeInterval, d > 0 { return d }
            if let d = heics[kCGImagePropertyHEICSDelayTime] as? TimeInterval, d > 0 { return d }
        }
        return fallback
    }

    // MARK: AVFoundation (MP4 / MOV / M4V)

    private func decodeVideo(url: URL) -> AnimatedIcon? {
        let asset = AVURLAsset(url: url)
        let dur = CMTimeGetSeconds(asset.duration)
        guard dur > 0, dur.isFinite else { return nil }

        // Aim for ~15 fps capped to 180 frames so a 10-second clip stays under
        // ~3MB at typical icon resolutions. Long videos get under-sampled.
        let fps: Double = 15
        let frameCount = max(1, min(180, Int(dur * fps)))
        let step = dur / Double(frameCount)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter  = .zero
        // Cap output frame size so a 1080p source doesn't burn ~6MB per frame.
        generator.maximumSize = CGSize(width: maxFrameDimension, height: maxFrameDimension)

        var frames: [CGImage] = []
        for i in 0..<frameCount {
            let t = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
            if let cg = try? generator.copyCGImage(at: t, actualTime: nil) {
                frames.append(cg)
            }
        }
        guard !frames.isEmpty else { return nil }
        let durations = Array(repeating: step, count: frames.count)
        return AnimatedIcon(frames: frames, durations: durations)
    }
}
