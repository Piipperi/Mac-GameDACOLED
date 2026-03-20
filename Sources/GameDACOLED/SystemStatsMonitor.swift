import Foundation
import IOKit

struct SystemSnapshot {
    let cpuPercent: Int
    let gpuPercent: Int?
    let ramPercent: Int
    let timestamp: Date
}

final class SystemStatsMonitor {
    private var previousCPULoad: host_cpu_load_info_data_t?
    private var previousGPUPercent: Double?

    func snapshot(usesUnixCPUPercent: Bool) throws -> SystemSnapshot {
        let cpuPercent = try currentCPUPercent(usesUnixStylePercent: usesUnixCPUPercent)
        let ramPercent = try currentRAMPercent()
        let gpuPercent = currentGPUPercent()

        return SystemSnapshot(
            cpuPercent: cpuPercent,
            gpuPercent: gpuPercent,
            ramPercent: ramPercent,
            timestamp: Date()
        )
    }

    private func currentCPUPercent(usesUnixStylePercent: Bool) throws -> Int {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw AppError("Unable to read CPU statistics.")
        }

        let current = cpuInfo.cpu_ticks

        defer {
            previousCPULoad = cpuInfo
        }

        guard let previousCPULoad else {
            return 0
        }

        let previous = previousCPULoad.cpu_ticks
        let user = current.0 - previous.0
        let system = current.1 - previous.1
        let idle = current.2 - previous.2
        let nice = current.3 - previous.3
        let total = user + system + idle + nice

        guard total > 0 else { return 0 }
        let active = user + system + nice
        let normalized = Double(active) / Double(total) * 100

        if usesUnixStylePercent {
            return Int((normalized * Double(ProcessInfo.processInfo.activeProcessorCount)).rounded())
        }

        return Int(normalized.rounded())
    }

    private func currentRAMPercent() throws -> Int {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw AppError("Unable to read memory statistics.")
        }

        let active = UInt64(stats.active_count) * UInt64(pageSize)
        let speculative = UInt64(stats.speculative_count) * UInt64(pageSize)
        let inactive = UInt64(stats.inactive_count) * UInt64(pageSize)
        let wired = UInt64(stats.wire_count) * UInt64(pageSize)
        let compressed = UInt64(stats.compressor_page_count) * UInt64(pageSize)
        let purgeable = UInt64(stats.purgeable_count) * UInt64(pageSize)
        let external = UInt64(stats.external_page_count) * UInt64(pageSize)

        let usedBytes = active + inactive + speculative + wired + compressed
            - min(purgeable + external, active + inactive + speculative + wired + compressed)
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        guard totalBytes > 0 else { return 0 }
        return Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())
    }

    private func currentGPUPercent() -> Int? {
        let samples = allGPUSamples()
        guard !samples.isEmpty else {
            return nil
        }
        let strongestSample = samples.max() ?? 0
        let smoothed = if let previousGPUPercent {
            strongestSample >= previousGPUPercent
                ? strongestSample * 0.7 + previousGPUPercent * 0.3
                : strongestSample * 0.55 + previousGPUPercent * 0.45
        } else {
            strongestSample
        }

        previousGPUPercent = smoothed
        return Int(smoothed.rounded())
    }

    private func allGPUSamples() -> [Double] {
        let classes = ["IOAccelerator", "AGXAccelerator"]
        var samples: [Double] = []

        for className in classes {
            let matching = IOServiceMatching(className)
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS {
                continue
            }

            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }

                if let properties = copyProperties(for: service) {
                    samples.append(contentsOf: gpuUtilizationSamples(from: properties))
                }
            }
        }

        return samples
    }

    private func gpuUtilizationSamples(from properties: [String: Any]) -> [Double] {
        let dictionaries = [
            properties["PerformanceStatistics"] as? [String: Any],
            properties["PerformanceStatisticsAccum"] as? [String: Any],
            properties["PerformanceStatisticsDictionary"] as? [String: Any]
        ].compactMap { $0 }

        let primaryKeys = [
            "Device Utilization %",
            "GPU Activity(%)",
            "GPU Activity %",
            "GPU Usage %"
        ]
        let secondaryKeys = [
            "Renderer Utilization %",
            "Tiler Utilization %",
            "Device Unit 0 Utilization %",
            "Device Unit 1 Utilization %",
            "Device Unit 2 Utilization %",
            "Device Unit 3 Utilization %",
            "GPU Core Utilization %",
            "GPU Busy %"
        ]

        var values: [Double] = []
        for dictionary in dictionaries {
            let primary = primaryKeys.compactMap { normalizeUtilizationValue(dictionary[$0]) }.first(where: { $0 > 0 })
            let secondaryValues = secondaryKeys.compactMap { normalizeUtilizationValue(dictionary[$0]) }
            let secondary = secondaryValues.isEmpty ? nil : secondaryValues.max()

            if let primary {
                values.append(primary)
            } else if let secondary {
                values.append(secondary)
            }
        }

        return values
    }

    private func normalizeUtilizationValue(_ value: Any?) -> Double? {
        guard let value else {
            return nil
        }

        let numericValue: Double?
        if let number = value as? NSNumber {
            numericValue = number.doubleValue
        } else if let doubleValue = value as? Double {
            numericValue = doubleValue
        } else if let intValue = value as? Int {
            numericValue = Double(intValue)
        } else {
            numericValue = nil
        }

        guard let numericValue else {
            return nil
        }

        if numericValue <= 1 {
            return numericValue * 100
        }

        if numericValue <= 100 {
            return numericValue
        }

        if numericValue <= 10_000 {
            return numericValue / 100
        }

        if numericValue <= 1_000_000 {
            return numericValue / 10_000
        }

        return nil
    }

    private func copyProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS else {
            return nil
        }

        return properties?.takeRetainedValue() as? [String: Any]
    }
}
