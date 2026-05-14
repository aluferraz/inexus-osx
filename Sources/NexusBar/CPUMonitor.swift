import Foundation
import Darwin

/// Aggregate host CPU load (user + system + nice + idle). Sample once per
/// interval and read `usage` for the 0...1 active fraction since the last call.
final class CPUMonitor {
    private var lastUser: UInt32 = 0
    private var lastSystem: UInt32 = 0
    private var lastIdle: UInt32 = 0
    private var lastNice: UInt32 = 0
    private(set) var usage: Double = 0

    func sample() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        let dUser = user &- lastUser
        let dSystem = system &- lastSystem
        let dIdle = idle &- lastIdle
        let dNice = nice &- lastNice

        let busy = Double(dUser) + Double(dSystem) + Double(dNice)
        let total = busy + Double(dIdle)
        if total > 0 { usage = busy / total }

        lastUser = user
        lastSystem = system
        lastIdle = idle
        lastNice = nice
    }
}
