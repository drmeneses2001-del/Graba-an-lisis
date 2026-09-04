import Foundation
import Darwin
import os

/// Lectura barata del consumo real de memoria del proceso.
///
/// `phys_footprint` es exactamente la cifra contra la que iOS mide antes de
/// matar el proceso, asi que es la unica que sirve para poner limites. Los
/// contadores de `ProcessInfo` no lo son.
enum MemoryReporter {

    /// Huella fisica actual del proceso, en bytes.
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    /// Lo que el sistema todavia nos deja consumir antes de matarnos. En la
    /// extension de difusion este numero arranca cerca de 50 MB; en la app
    /// depende del dispositivo y de lo que haya en segundo plano.
    static func availableBytes() -> UInt64 {
        let available = os_proc_available_memory()
        return available > 0 ? UInt64(available) : 0
    }

    /// Techo estimado del proceso: lo consumido mas lo que queda.
    static func estimatedLimitBytes() -> UInt64 {
        let available = availableBytes()
        guard available > 0 else { return 0 }
        return footprintBytes() + available
    }

    /// RAM fisica del dispositivo.
    static var physicalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Espacio libre en el volumen donde guardamos el audio.
    static func freeDiskBytes() -> UInt64 {
        let values = try? AppGroup.containerURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage {
            return UInt64(max(0, capacity))
        }
        return 0
    }

    static func formatted(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
