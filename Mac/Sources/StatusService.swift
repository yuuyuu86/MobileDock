//
//  StatusService.swift
//  MobileDock for Mac — the glanceable numbers the remote shows on its status page.
//

import Foundation
import AppKit
import IOKit.ps

@MainActor
final class StatusService {

    private var previousTicks: (user: Double, system: Double, idle: Double, nice: Double)?
    /// Brightness has no public setter or getter, so we track what we asked for.
    private(set) var brightnessEstimate: Double = 0.7
    private var cachedNowPlaying: NowPlaying?
    private var lastNowPlayingFetch = Date.distantPast

    func snapshot() -> MacStatus {
        let memory = memoryUsage()
        return MacStatus(batteryPercent: battery()?.percent,
                         isCharging: battery()?.charging ?? false,
                         cpuPercent: cpuUsage(),
                         memoryUsedGB: memory.used,
                         memoryTotalGB: memory.total,
                         diskFreeGB: diskFree(),
                         volume: volume(),
                         isMuted: isMuted(),
                         brightness: brightnessEstimate,
                         networkName: networkName(),
                         uptime: uptime(),
                         nowPlaying: nowPlaying())
    }

    func noteBrightness(_ level: Double) {
        brightnessEstimate = min(1, max(0, level))
    }

    // MARK: Battery

    private func battery() -> (percent: Int, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return (Int((Double(current) / Double(max)) * 100), charging)
        }
        return nil
    }

    // MARK: CPU

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        defer { previousTicks = (user, system, idle, nice) }
        guard let previous = previousTicks else { return 0 }

        let userDelta = user - previous.user
        let systemDelta = system - previous.system
        let idleDelta = idle - previous.idle
        let niceDelta = nice - previous.nice
        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return 0 }
        return ((userDelta + systemDelta + niceDelta) / total) * 100
    }

    // MARK: Memory & disk

    private func memoryUsage() -> (used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }

        let pageSize = Double(vm_kernel_page_size)
        // "Used" the way Activity Monitor counts it: everything but free and purgeable.
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        return ((active + wired + compressed) / 1_073_741_824, total)
    }

    private func diskFree() -> Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Double(available) / 1_073_741_824
    }

    // MARK: Sound

    private func volume() -> Double {
        guard let output = Shell.run("/usr/bin/osascript",
                                     ["-e", "output volume of (get volume settings)"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(output) else { return 0 }
        return value / 100
    }

    private func isMuted() -> Bool {
        let output = Shell.run("/usr/bin/osascript",
                               ["-e", "output muted of (get volume settings)"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "true"
    }

    // MARK: Machine

    private func networkName() -> String? {
        // The Wi-Fi SSID needs Location access on recent macOS; fall back to the
        // interface's own name so the panel still says something useful.
        if let ssid = Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", "en0"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let range = ssid.range(of: ": ") {
            return String(ssid[range.upperBound...])
        }
        return Host.current().localizedName
    }

    private func uptime() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: Now playing

    private func nowPlaying() -> NowPlaying? {
        // AppleScript is slow, so only ask a couple of times a minute.
        if Date().timeIntervalSince(lastNowPlayingFetch) > 20 {
            lastNowPlayingFetch = Date()
            Task.detached(priority: .utility) {
                let fetched = StatusService.fetchNowPlaying()
                await MainActor.run { self.cachedNowPlaying = fetched }
            }
        }
        return cachedNowPlaying
    }

    private nonisolated static func fetchNowPlaying() -> NowPlaying? {
        for app in ["Music", "Spotify"] {
            let script = """
            if application "\(app)" is running then
                tell application "\(app)"
                    if player state is playing or player state is paused then
                        return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as text)
                    end if
                end tell
            end if
            return ""
            """
            guard let output = Shell.run("/usr/bin/osascript", ["-e", script])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { continue }
            let parts = output.components(separatedBy: "\n")
            guard parts.count >= 3 else { continue }
            return NowPlaying(title: parts[0],
                              artist: parts[1],
                              app: app,
                              isPlaying: parts[2].contains("playing"))
        }
        return nil
    }

    // MARK: Setters

    func setVolume(_ level: Double) {
        let percent = Int(min(1, max(0, level)) * 100)
        Task.detached { Shell.run("/usr/bin/osascript", ["-e", "set volume output volume \(percent)"], capture: false) }
    }

    func setMuted(_ muted: Bool) {
        Task.detached {
            Shell.run("/usr/bin/osascript", ["-e", "set volume \(muted ? "with" : "without") output muted"], capture: false)
        }
    }
}
