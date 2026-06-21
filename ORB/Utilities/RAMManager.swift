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

    /// Total installed physical RAM, in GB.
    private var totalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }

    /// Memory macOS can hand out *right now* without paging the user's working set
    /// to disk, in GB.
    ///
    /// This mirrors Activity Monitor's "Memory Used": app memory (anonymous pages,
    /// minus purgeable) + wired + compressed. Everything else — free pages plus the
    /// reclaimable file-backed caches — is available. We deliberately do NOT look at
    /// `free_count` alone: on macOS that number sits near zero because the OS keeps
    /// RAM busy with caches it reclaims on demand, so a `free_count` test reports
    /// "low memory" even on a near-idle machine. That false trip is exactly why a
    /// freshly loaded 2.5 GB Gemma model made every command fail.
    func availableMemoryGB() -> Double {
        guard let stats = vmStats() else { return totalMemoryGB }
        let pageSize = Double(vm_kernel_page_size)
        let usedBytes = (Double(stats.internal_page_count) - Double(stats.purgeable_count)
                         + Double(stats.wire_count)
                         + Double(stats.compressor_page_count)) * pageSize
        return max(0, totalMemoryGB - usedBytes / 1_073_741_824.0)
    }

    /// The kernel's own memory-pressure verdict
    /// (`kern.memorystatus_vm_pressure_level`): 1 = normal, 2 = warning,
    /// 4 = critical. This is the signal macOS itself uses before it starts
    /// jettisoning memory, so it's a far better "should I refuse this command?"
    /// test than any hand-picked free-RAM threshold.
    private func memoryPressureLevel() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return ok == 0 ? Int(level) : 1
    }

    /// Refuse a command only when the machine genuinely can't take the working set:
    /// the kernel reports *critical* pressure, or there's less reclaimable memory
    /// left than inference needs for scratch. This matches how Google AI Edge
    /// Gallery behaves — load the model and let the OS page/compress/reclaim,
    /// rather than pre-emptively gating on a misleading free-page count.
    var isLowMemory: Bool {
        if memoryPressureLevel() >= 4 { return true }
        return availableMemoryGB() < 0.5
    }

    /// Free physical memory in GB. Kept for any callers that want a coarse number;
    /// reports *available* (reclaimable) memory, not the near-useless `free_count`.
    func freeMemoryGB() -> Double { availableMemoryGB() }

    private func vmStats() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// Reflect the real resident footprint of the process for the current phase.
    func setPhase(_ state: AgentState) {
        displayedMB = appResidentMB()
    }
}
