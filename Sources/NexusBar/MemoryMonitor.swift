import Foundation
import Darwin

/// Coarse system memory pressure: returns the fraction of physical RAM that
/// the kernel reports as active+wired+compressed (i.e. not free / inactive).
final class MemoryMonitor {
    private(set) var usage: Double = 0       // 0...1
    private(set) var usedBytes: UInt64 = 0
    let totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    func sample() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired  = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        usedBytes = active + wired + compressed
        usage = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
}
