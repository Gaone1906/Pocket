import AppKit
import Darwin
import IOKit.ps
import SwiftUI

struct BatteryReading: Equatable {
    var percent: Int
    var charging: Bool
    var onAC: Bool
}

struct DiskReading: Equatable {
    var free: Int64
    var total: Int64
    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }
}

final class StatsSampler {
    private var previousCPU: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNet: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var previousNetAt: Date?
    private var reportedFailures = Set<String>()

    private func report(_ kind: String, code: Int32) {
        guard reportedFailures.insert(kind).inserted else { return }
        note("pocket stats failure kind=\(kind) code=\(code)")
    }

    func cpuPercent() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            report("host_statistics.cpu", code: result)
            return nil
        }
        let current = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { previousCPU = current }
        guard let previous = previousCPU else { return nil }
        let user = Double(current.user &- previous.user)
        let system = Double(current.system &- previous.system)
        let idle = Double(current.idle &- previous.idle)
        let nice = Double(current.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return min(100, max(0, (user + system + nice) / total * 100))
    }

    func resetCPU() { previousCPU = nil }

    func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            report("host_statistics64.vm", code: result)
            return nil
        }
        let pages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count) &+ UInt64(stats.wire_count) &+ UInt64(stats.compressor_page_count)
        return (pages * UInt64(vm_kernel_page_size), ProcessInfo.processInfo.physicalMemory)
    }

    func memoryPressurePercent() -> Int? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0)
        guard result == 0 else {
            report("sysctl.memorystatus_level", code: errno)
            return nil
        }
        return min(100, max(0, 100 - Int(level)))
    }

    func disk() -> DiskReading? {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            guard let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity else {
                report("disk.capacity_missing", code: -1)
                return nil
            }
            return DiskReading(free: free, total: Int64(total))
        } catch {
            report("disk.resource_values", code: Int32((error as NSError).code))
            return nil
        }
    }

    private func delta(_ current: UInt32, _ previous: UInt32) -> UInt64 {
        current >= previous ? UInt64(current - previous) : UInt64(current) + UInt64(UInt32.max) + 1 - UInt64(previous)
    }

    func network() -> (down: Double, up: Double)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            report("getifaddrs", code: errno)
            return nil
        }
        defer { freeifaddrs(head) }
        var current: [String: (rx: UInt32, tx: UInt32)] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (counters.ifi_ibytes, counters.ifi_obytes)
        }
        let now = Date()
        defer {
            previousNet = current
            previousNetAt = now
        }
        guard let at = previousNetAt else { return nil }
        let seconds = now.timeIntervalSince(at)
        guard seconds > 0 else { return nil }
        var down: UInt64 = 0
        var up: UInt64 = 0
        for (name, counters) in current {
            guard let previous = previousNet[name] else { continue }
            down += delta(counters.rx, previous.rx)
            up += delta(counters.tx, previous.tx)
        }
        return (Double(down) / seconds, Double(up) / seconds)
    }

    func resetNetwork() {
        previousNet = [:]
        previousNetAt = nil
    }

    func battery() -> BatteryReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            report("iops.snapshot", code: -1)
            return nil
        }
        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            report("iops.list", code: -1)
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return BatteryReading(percent: min(100, current * 100 / maximum), charging: charging, onAC: onAC)
        }
        return nil
    }

    func bootDate() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            report("sysctl.boottime", code: errno)
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }
}

final class StatsModel: ObservableObject {
    @Published var cpu = 0.0
    @Published var hasCPU = false
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var pressure = 0
    @Published var disk: DiskReading?
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var battery: BatteryReading?
    @Published var uptime: TimeInterval = 0
    @Published var thermal = ProcessInfo.processInfo.thermalState
    @Published var cpuInBar: Bool {
        didSet {
            guard oldValue != cpuInBar else { return }
            UserDefaults.standard.set(cpuInBar, forKey: "stats.cpuInBar")
            onToggle?(cpuInBar)
        }
    }
    var onToggle: ((Bool) -> Void)?

    init() {
        cpuInBar = UserDefaults.standard.bool(forKey: "stats.cpuInBar")
    }

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

final class StatsApp: PocketApp {
    private let model = StatsModel()
    private let sampler = StatsSampler()
    private var panelTimer: Timer?
    private var barTimer: Timer?

    override init(spec: AppSpec) {
        super.init(spec: spec)
        model.onToggle = { [weak self] enabled in self?.barToggled(enabled) }
    }

    override var defaultSize: NSSize { NSSize(width: 340, height: 420) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        ThemedHostingView(rootView: StatsView(model: model))
    }

    override func start() {
        if model.cpuInBar { startBarTimer() }
    }

    override func stop() {
        panelTimer?.invalidate()
        panelTimer = nil
        barTimer?.invalidate()
        barTimer = nil
        super.stop()
    }

    override func didShow() {
        sampler.resetNetwork()
        sampleAll()
        panelTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sampleAll() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        panelTimer = timer
    }

    override func didHide() {
        panelTimer?.invalidate()
        panelTimer = nil
        sampler.resetNetwork()
        if model.cpuInBar {
            sampler.resetCPU()
            _ = sampler.cpuPercent()
        }
    }

    override func barTitle() -> NSAttributedString? {
        guard model.cpuInBar, model.hasCPU else { return nil }
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        return NSAttributedString(string: String(format: " %d%%", Int(model.cpu.rounded())),
                                  attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)])
    }

    private func barToggled(_ enabled: Bool) {
        if enabled {
            startBarTimer()
        } else {
            barTimer?.invalidate()
            barTimer = nil
        }
        note("pocket stats cpu in bar app=\(spec.id) enabled=\(enabled)")
        changed()
    }

    private func startBarTimer() {
        barTimer?.invalidate()
        sampler.resetCPU()
        _ = sampler.cpuPercent()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.sampleBar() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        barTimer = timer
    }

    private func sampleBar() {
        guard model.cpuInBar, !isShown else { return }
        if let cpu = sampler.cpuPercent() {
            model.cpu = cpu
            model.hasCPU = true
        }
        changed()
    }

    private func sampleAll() {
        if let cpu = sampler.cpuPercent() {
            model.cpu = cpu
            model.hasCPU = true
        }
        if let memory = sampler.memory() {
            model.memoryUsed = memory.used
            model.memoryTotal = memory.total
        }
        model.pressure = sampler.memoryPressurePercent() ?? model.pressure
        model.disk = sampler.disk()
        if let net = sampler.network() {
            model.down = net.down
            model.up = net.up
        }
        model.battery = sampler.battery()
        model.uptime = sampler.bootDate().map { Date().timeIntervalSince($0) } ?? model.uptime
        model.thermal = ProcessInfo.processInfo.thermalState
        if model.cpuInBar { changed() }
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    let gigabytes = Double(bytes) / 1_073_741_824
    return gigabytes >= 100 ? String(format: "%.0f GB", gigabytes) : String(format: "%.1f GB", gigabytes)
}

private func formatRate(_ bytesPerSecond: Double) -> String {
    let kilobytes = bytesPerSecond / 1024
    if kilobytes >= 1024 { return String(format: "%.1f MB/s", kilobytes / 1024) }
    return String(format: "%.0f KB/s", kilobytes)
}

private func formatUptime(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
    if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

private func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "Nominal"
    case .fair: return "Fair"
    case .serious: return "Serious"
    case .critical: return "Critical"
    @unknown default: return "Unknown"
    }
}

private func meterColor(_ fraction: Double) -> Color {
    fraction >= 0.9 ? Color(hue: 4, saturation: 62, lightness: 58) : fraction >= 0.7 ? Color(hue: 30, saturation: 70, lightness: 58) : Board.accent
}

private struct Meter: View {
    let fraction: Double
    var tint: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Board.ink.opacity(0.1))
                Capsule()
                    .fill(tint ?? meterColor(fraction))
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

private struct MeterRow: View {
    let label: String
    let value: String
    let fraction: Double
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Board.ink)
                Spacer()
                Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Board.ink)
            }
            Meter(fraction: fraction)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(Board.muted)
            }
        }
    }
}

private struct StatsView: View {
    @ObservedObject var model: StatsModel
    @ObservedObject var themes = BoardThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeterRow(label: "CPU", value: String(format: "%.0f%%", model.cpu), fraction: model.cpu / 100)
            MeterRow(label: "Memory",
                     value: "\(formatBytes(model.memoryUsed)) / \(formatBytes(model.memoryTotal))",
                     fraction: model.memoryFraction,
                     detail: "Pressure \(model.pressure)%")
            if let disk = model.disk {
                MeterRow(label: "Disk",
                         value: "\(formatBytes(UInt64(max(0, disk.free)))) free",
                         fraction: disk.usedFraction,
                         detail: "of \(formatBytes(UInt64(max(0, disk.total))))")
            }
            HStack {
                Text("Network").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\u{2193} \(formatRate(model.down))   \u{2191} \(formatRate(model.up))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(Board.ink)
            if let battery = model.battery {
                MeterRow(label: "Battery",
                         value: "\(battery.percent)%",
                         fraction: Double(battery.percent) / 100,
                         detail: battery.charging ? "Charging" : battery.onAC ? "On power" : "On battery")
            }
            Spacer(minLength: 0)
            Rectangle().fill(Board.line.opacity(themes.theme.embroidery == nil ? 1 : 0.35)).frame(height: 1)
            Toggle("Show CPU in menu bar", isOn: $model.cpuInBar)
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .foregroundStyle(Board.ink)
            HStack {
                Text("Uptime \(formatUptime(model.uptime))")
                Spacer()
                Text("Thermal \(thermalLabel(model.thermal))")
            }
            .font(.system(size: 11))
            .foregroundStyle(Board.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(themes.theme.id)
        .background(ReadableBackdrop(theme: themes.theme, dim: 0.6).ignoresSafeArea())
        .environment(\.colorScheme, themes.theme.colorScheme)
        .tint(themes.theme.accent)
    }
}
