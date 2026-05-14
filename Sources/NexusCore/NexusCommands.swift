import Foundation

extension NexusDevice {

    // MARK: - Control commands (Feature report 0x03)

    /// Sets the display backlight, 0...100. 0 turns it off.
    public func setBrightness(_ percent: Int) throws {
        let clamped = UInt8(max(0, min(100, percent)))
        try writeFeatureReport([
            NexusProtocol.controlReportId,
            NexusProtocol.Control.setBacklight.rawValue,
            clamped,
        ])
    }

    /// Clears the screen to black without changing brightness state.
    public func blankScreen() throws {
        try writeFeatureReport([
            NexusProtocol.controlReportId,
            NexusProtocol.Control.blankScreen.rawValue,
        ])
    }

    /// Plays one of the three firmware-embedded animations (1...3).
    public func playAnimation(_ index: Int, loop: Bool) throws {
        precondition((1...3).contains(index), "animation index must be 1...3")
        try writeFeatureReport([
            NexusProtocol.controlReportId,
            NexusProtocol.Control.playAnimation.rawValue,
            UInt8(index),
            loop ? 1 : 0,
        ])
    }

    public func stopAnimation() throws {
        try writeFeatureReport([
            NexusProtocol.controlReportId,
            NexusProtocol.Control.stopAnimation.rawValue,
        ])
    }

    // MARK: - Image upload (Output report 0x02)

    /// Push a full 640x48 RGBA32 frame to the display.
    /// Bytes are laid out row-major, 4 bytes per pixel: R, G, B, A.
    public func showFrame(_ rgba: [UInt8]) throws {
        guard rgba.count == NexusProtocol.frameByteCount else {
            throw NexusError.invalidFrameSize(expected: NexusProtocol.frameByteCount, actual: rgba.count)
        }

        let chunkSize = NexusProtocol.imageChunkPayloadBytes
        var report = [UInt8](repeating: 0, count: NexusProtocol.imageReportTotalBytes)
        report[0] = NexusProtocol.imageReportId // 0x02
        report[1] = 0x05                        // command
        report[2] = 0x40                        // sub-command / type

        var offset = 0
        var blockNumber: UInt16 = 0

        while offset < rgba.count {
            let remaining = rgba.count - offset
            let payloadLen = min(chunkSize, remaining)
            let isLast = (remaining - payloadLen) == 0

            report[3] = isLast ? 1 : 0
            report[4] = UInt8(blockNumber & 0xFF)
            report[5] = UInt8((blockNumber >> 8) & 0xFF)
            report[6] = UInt8(payloadLen & 0xFF)
            report[7] = UInt8((payloadLen >> 8) & 0xFF)

            // Copy payload into report[8..<8+payloadLen]. Tail bytes from a previous
            // chunk are harmless; the device uses payloadLen to know what's real.
            rgba.withUnsafeBufferPointer { src in
                report.withUnsafeMutableBufferPointer { dst in
                    let srcStart = src.baseAddress!.advanced(by: offset)
                    let dstStart = dst.baseAddress!.advanced(by: NexusProtocol.imageHeaderBytes)
                    dstStart.update(from: srcStart, count: payloadLen)
                }
            }

            try writeOutputReport(report)

            offset += payloadLen
            blockNumber &+= 1
        }
    }
}

// MARK: - Gesture recognizer

/// Collapses a stream of `NexusTouchEvent`s into discrete gestures, matching
/// NexusTool's interpretation: small displacement = tap, larger = jitter,
/// > 200 px = swipe.
public final class NexusGestureRecognizer {
    public var swipeThreshold = 200
    public var tapThreshold = 50

    private var firstX: Int?
    private var lastX: Int = -1

    public init() {}

    /// Feed an event in. Returns a gesture when the touch completes (.ended).
    public func feed(_ event: NexusTouchEvent) -> NexusGesture? {
        switch event.phase {
        case .began:
            firstX = event.x
            lastX = event.x
            return nil
        case .moved:
            lastX = event.x
            return nil
        case .ended:
            defer { firstX = nil }
            guard let first = firstX else { return .tap(x: event.x) }
            let diff = lastX - first
            if diff > swipeThreshold { return .swipeRight }
            if diff < -swipeThreshold { return .swipeLeft }
            if abs(diff) > tapThreshold { return .jitter(x: first) }
            return .tap(x: first)
        }
    }
}
