import Foundation
import CoreGraphics
import ImageIO

/// Helpers that produce a 640×48 RGBA8 byte array ready for `NexusDevice.showFrame`.
public enum NexusImage {

    /// How to fit a source image into the 640×48 frame.
    public enum ScaleMode: String, Sendable, CaseIterable {
        case stretch   // ignore aspect, fill the panel
        case fit       // uniform scale to fit; bars on the short axis
        case fill      // uniform scale to fill; crops overflow
        case center    // 1:1 at source resolution, centered

        public var displayName: String {
            switch self {
            case .stretch: return "Stretch"
            case .fit:     return "Fit (letterbox)"
            case .fill:    return "Fill (crop)"
            case .center:  return "Center (1:1)"
            }
        }
    }

    /// Loads an image from disk and renders it to a 640×48 RGBA8 frame.
    public static func loadAsFrame(url: URL, mode: ScaleMode = .stretch) throws -> [UInt8] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "NexusImage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not decode \(url.lastPathComponent)"])
        }
        return try rasterize(cgImage: cg, mode: mode)
    }

    /// Rasterizes any CGImage to 640×48 RGBA8 using the supplied scale mode.
    public static func rasterize(cgImage: CGImage, mode: ScaleMode = .stretch) throws -> [UInt8] {
        let w = CGFloat(NexusProtocol.width)
        let h = CGFloat(NexusProtocol.height)
        let sw = CGFloat(cgImage.width)
        let sh = CGFloat(cgImage.height)

        let drawRect: CGRect
        switch mode {
        case .stretch:
            drawRect = CGRect(x: 0, y: 0, width: w, height: h)
        case .fit:
            let scale = min(w / sw, h / sh)
            let nw = sw * scale, nh = sh * scale
            drawRect = CGRect(x: (w - nw) / 2, y: (h - nh) / 2, width: nw, height: nh)
        case .fill:
            let scale = max(w / sw, h / sh)
            let nw = sw * scale, nh = sh * scale
            drawRect = CGRect(x: (w - nw) / 2, y: (h - nh) / 2, width: nw, height: nh)
        case .center:
            drawRect = CGRect(x: (w - sw) / 2, y: (h - sh) / 2, width: sw, height: sh)
        }

        return try renderToFrame { ctx in
            ctx.interpolationQuality = .high
            // The outer renderToFrame already flipped Y so callers think top-down.
            // CG image drawing is most natural in bottom-up, so flip locally around
            // the destination rect, draw, then restore.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: drawRect.minY + drawRect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: drawRect)
            ctx.restoreGState()
        }
    }

    /// Render arbitrary Core Graphics drawing into a 640×48 frame. If `background`
    /// is supplied (and the right size) it pre-fills the buffer so the closure
    /// draws on top of it; otherwise the buffer starts black.
    /// The closure receives a context in top-left origin coordinates.
    public static func renderToFrame(background: [UInt8]? = nil,
                                     _ draw: (CGContext) -> Void) throws -> [UInt8] {
        let w = NexusProtocol.width
        let h = NexusProtocol.height
        let bytesPerRow = w * NexusProtocol.pixelStride
        var pixels: [UInt8]
        if let bg = background, bg.count == w * h * NexusProtocol.pixelStride {
            pixels = bg
        } else {
            pixels = [UInt8](repeating: 0, count: w * h * NexusProtocol.pixelStride)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                       | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = pixels.withUnsafeMutableBufferPointer({ ptr -> CGContext? in
            CGContext(data: ptr.baseAddress,
                      width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                      space: colorSpace, bitmapInfo: bitmapInfo)
        }) else {
            throw NSError(domain: "NexusImage", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        // Flip so the closure sees top-left origin (matching the panel).
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        draw(ctx)

        // Force alpha to 0xFF since the firmware ignores it but stale bytes look bad.
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 0xFF }
        return pixels
    }

    /// Convert a 640×48 RGBA8 byte array back into a CGImage. Useful for previews.
    public static func cgImage(from frame: [UInt8]) -> CGImage? {
        guard frame.count == NexusProtocol.frameByteCount else { return nil }
        let w = NexusProtocol.width
        let h = NexusProtocol.height
        let bytesPerRow = w * NexusProtocol.pixelStride
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                       | CGBitmapInfo.byteOrder32Big.rawValue
        var copy = frame
        let provider = copy.withUnsafeMutableBufferPointer { ptr -> CGDataProvider? in
            guard let base = ptr.baseAddress else { return nil }
            let data = Data(bytes: base, count: ptr.count)
            return CGDataProvider(data: data as CFData)
        }
        guard let provider else { return nil }
        return CGImage(width: w, height: h,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
