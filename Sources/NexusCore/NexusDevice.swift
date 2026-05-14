import Foundation
import IOKit
import IOKit.hid

/// Errors produced by the Nexus HID layer.
public enum NexusError: Error, CustomStringConvertible {
    case deviceNotFound
    case openFailed(IOReturn)
    case setReportFailed(IOReturn)
    case getReportFailed(IOReturn)
    case invalidFrameSize(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .deviceNotFound:
            return "Corsair iCUE Nexus (VID 0x1B1C / PID 0x1B8E) not found."
        case .openFailed(let r):
            return "IOHIDDeviceOpen failed: 0x\(String(r, radix: 16))"
        case .setReportFailed(let r):
            return "IOHIDDeviceSetReport failed: 0x\(String(r, radix: 16))"
        case .getReportFailed(let r):
            return "IOHIDDeviceGetReport failed: 0x\(String(r, radix: 16))"
        case .invalidFrameSize(let e, let a):
            return "Frame must be \(e) bytes (RGBA32 \(NexusProtocol.width)x\(NexusProtocol.height)), got \(a)."
        }
    }
}

/// Talks to a single Nexus over IOHIDDevice. Thread-safe for protocol writes;
/// touch callbacks fire on the run loop the device was opened on.
public final class NexusDevice {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let writeLock = NSLock()
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private var touchHandler: ((NexusTouchEvent) -> Void)?
    private var lastTouchActive = false

    private init(manager: IOHIDManager, device: IOHIDDevice) {
        self.manager = manager
        self.device = device
    }

    // MARK: Discovery / lifecycle

    /// Locate the operational interface (Usage Page 0x000C) on the connected Nexus
    /// and open it for I/O. Must be called on a thread with an active run loop if
    /// you intend to receive touch callbacks; for one-shot writes, any thread is fine.
    public static func open() throws -> NexusDevice {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: NexusProtocol.vendorId,
            kIOHIDProductIDKey as String: NexusProtocol.productId,
            kIOHIDDeviceUsagePageKey as String: NexusProtocol.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw NexusError.openFailed(openResult)
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else {
            throw NexusError.deviceNotFound
        }

        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw NexusError.openFailed(r) }

        return NexusDevice(manager: manager, device: dev)
    }

    public func close() {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: Identity (Feature report 5)

    /// Read a feature report (e.g. firmware info on report 5).
    public func readFeatureReport(id: UInt8, length: Int = 64) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer { ptr -> IOReturn in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), ptr.baseAddress!, &reportLength)
        }
        guard r == kIOReturnSuccess else { throw NexusError.getReportFailed(r) }
        return Array(buf.prefix(Int(reportLength)))
    }

    /// Decodes the firmware version embedded in Feature report 5.
    public func firmwareVersion() throws -> String {
        let bytes = try readFeatureReport(id: NexusProtocol.infoReportId)
        guard bytes.count > 6 else { return "" }
        let tail = bytes.dropFirst(6)
        let end = tail.firstIndex(of: 0) ?? tail.endIndex
        return String(bytes: tail[tail.startIndex..<end], encoding: .ascii) ?? ""
    }

    // MARK: Output reports (image upload)

    /// Send a single output report. `body` must include the report ID as byte 0,
    /// matching hidapi's convention on macOS.
    func writeOutputReport(_ body: [UInt8]) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        let reportID = CFIndex(body[0])
        let r = body.withUnsafeBufferPointer { ptr -> IOReturn in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID,
                                 ptr.baseAddress!, CFIndex(body.count))
        }
        guard r == kIOReturnSuccess else { throw NexusError.setReportFailed(r) }
    }

    /// Send a feature report. `body` must include the report ID as byte 0.
    func writeFeatureReport(_ body: [UInt8]) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        let reportID = CFIndex(body[0])
        let r = body.withUnsafeBufferPointer { ptr -> IOReturn in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, reportID,
                                 ptr.baseAddress!, CFIndex(body.count))
        }
        guard r == kIOReturnSuccess else { throw NexusError.setReportFailed(r) }
    }

    // MARK: Input reports (touch)

    /// Register a callback invoked on every input report. The device must have
    /// been opened on a thread with an active run loop, and that run loop must
    /// be scheduled via `scheduleOnRunLoop(_:mode:)`.
    public func onTouch(_ handler: @escaping (NexusTouchEvent) -> Void) {
        self.touchHandler = handler
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { ptr in
            IOHIDDeviceRegisterInputReportCallback(
                device,
                ptr.baseAddress!,
                CFIndex(ptr.count),
                { ctx, _, _, _, reportID, report, reportLength in
                    guard let ctx else { return }
                    let me = Unmanaged<NexusDevice>.fromOpaque(ctx).takeUnretainedValue()
                    let buf = UnsafeBufferPointer(start: report, count: Int(reportLength))
                    me.handleInputReport(reportID: UInt8(reportID), bytes: Array(buf))
                },
                opaque
            )
        }
    }

    public func scheduleOnRunLoop(_ runLoop: CFRunLoop = CFRunLoopGetCurrent(),
                                  mode: CFString = CFRunLoopMode.defaultMode.rawValue) {
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, mode)
    }

    public func unscheduleFromRunLoop(_ runLoop: CFRunLoop = CFRunLoopGetCurrent(),
                                      mode: CFString = CFRunLoopMode.defaultMode.rawValue) {
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, mode)
    }

    private func handleInputReport(reportID: UInt8, bytes: [UInt8]) {
        // IOKit hands us the report body *without* the report ID prefix.
        // For touch (report 0x01): body = [0x02, 0x21, 0x00, 0x00, state, x_lo, x_hi, ...].
        guard reportID == NexusProtocol.touchReportId,
              bytes.count >= 7,
              bytes[0] == 0x02, bytes[1] == 0x21
        else { return }

        let active = bytes[4] != 0
        let x = Int(bytes[5]) | (Int(bytes[6]) << 8)

        let phase: NexusTouchEvent.Phase
        switch (lastTouchActive, active) {
        case (false, true): phase = .began
        case (true, true):  phase = .moved
        case (true, false): phase = .ended
        case (false, false): return // no-op idle report
        }
        lastTouchActive = active
        touchHandler?(NexusTouchEvent(phase: phase, x: x))
    }
}
