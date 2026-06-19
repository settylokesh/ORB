//
//  RAMManager.swift
//  ORB
//
//  Reports app + system memory and models the lazy-loading RAM budget
//  described in the spec (idle 150 MB → Moonshine 123 MB → Gemma ~4 GB).
//

import Foundation
import Combine

@MainActor
final class RAMManager: ObservableObject {
    /// Approximate footprint we display for the current pipeline phase.
    @Published var displayedMB: Int = 150

    static let moonshineMB = 123
    static let gemmaMB = 4100
    static let idleMB = 150

    /// Real resident size of this process, in MB.
    func appResidentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return Self.idleMB }
        return Int(info.resident_size / (1024 * 1024))
    }

    /// Free physical memory in GB (used for the low-memory warning).
    func freeMemoryGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 8 }
        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        return Double(free) / 1_073_741_824.0
    }

    var isLowMemory: Bool { freeMemoryGB() < 1.0 }

    /// Reflect the real resident footprint of the process for the current phase.
    func setPhase(_ state: AgentState) {
        displayedMB = appResidentMB()
    }
}
