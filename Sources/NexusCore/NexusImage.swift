import Foundation
import CoreGraphics
import ImageIO

/// Helpers that produce a 640×48 RGBA8 byte array ready for `NexusDevice.showFrame`.
public enum NexusImage {

    /// Loads an image from disk and resizes (stretching aspect) to 640×48 RGBA8.
    public static func loadAsFrame(url: URL) throws -> [UInt8] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "NexusImage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not decode \(url.lastPathComponent)"])
        }
        return try rasterize(cgImage: cg)
    }

    /// Rasterizes any CGImage to 640×48 RGBA8.
    public static func rasterize(cgImage: CGImage) throws -> [UInt8] {
        return try renderToFrame { ctx in
            let rect = CGRect(x: 0, y: 0,
                              width: NexusProtocol.width,
                              height: NexusProtocol.height)
            ctx.interpolationQuality = .high
            // CG draws bottom-up; the display reads top-down. Flip once here so
            // callers can think in normal screen coordinates.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(NexusProtocol.height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: rect)
            ctx.restoreGState()
        }
    }

    /// Render arbitrary Core Graphics drawing into a 640×48 frame. The supplied
    /// closure receives a context in top-left origin coordinates (already flipped).
    public static func renderToFrame(_ draw: (CGContext) -> Void) throws -> [UInt8] {
        let w = NexusProtocol.width
        let h = NexusProtocol.height
        let bytesPerRow = w * NexusProtocol.pixelStride
        var pixels = [UInt8](repeating: 0, count: w * h * NexusProtocol.pixelStride)

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
}
