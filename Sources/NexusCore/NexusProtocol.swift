import Foundation

/// Wire-level constants for the Corsair iCUE Nexus.
///
/// Reverse-engineered from `willneedit/NexusTool` (Linux/hidapi).
/// The Nexus is a plain USB HID device on Interface 0 (Usage Page 0x000C);
/// Interface 1 (Usage Page 0x0001) is firmware-upload only and unused here.
public enum NexusProtocol {
    public static let vendorId: Int32 = 0x1B1C   // Corsair
    public static let productId: Int32 = 0x1B8E  // iCUE Nexus
    public static let usagePage: UInt32 = 0x000C // Operational interface

    /// Display dimensions, in pixels. Each pixel is RGBA8 (4 bytes).
    public static let width = 640
    public static let height = 48
    public static let pixelStride = 4
    public static let frameByteCount = width * height * pixelStride // 122,880

    // MARK: Report IDs

    /// Feature report carrying control commands (brightness, blank, animation, ...).
    public static let controlReportId: UInt8 = 0x03
    /// Feature report exposing firmware/identity info (read-only).
    public static let infoReportId: UInt8 = 0x05
    /// Output report carrying image upload chunks.
    public static let imageReportId: UInt8 = 0x02
    /// Input report ID for touch events.
    public static let touchReportId: UInt8 = 0x01

    // MARK: Control sub-commands (second byte of Feature 0x03)

    public enum Control: UInt8 {
        case setBacklight = 0x01
        case blankScreen = 0x04
        case stopAnimation = 0x0F
        case playAnimation = 0x0D
        case unknown10 = 0x10
    }

    // MARK: Image upload framing

    /// Each output report sent to the device is 1024 bytes total (incl. report ID).
    /// The first 8 bytes are a block header; the remaining 1016 carry RGBA pixels.
    public static let imageReportTotalBytes = 1024
    public static let imageHeaderBytes = 8
    public static let imageChunkPayloadBytes = imageReportTotalBytes - imageHeaderBytes // 1016
}

/// A touch event reported by the Nexus on report ID 0x01.
public struct NexusTouchEvent: Equatable, Sendable {
    public enum Phase: Sendable { case began, moved, ended }
    public let phase: Phase
    /// X coordinate in display space, 0...639. Left edge is 0.
    public let x: Int
}

/// High-level touch interpretation across a press/release cycle.
public enum NexusGesture: Equatable, Sendable {
    case tap(x: Int)
    case jitter(x: Int)
    case swipeLeft
    case swipeRight
    case timeout
}
