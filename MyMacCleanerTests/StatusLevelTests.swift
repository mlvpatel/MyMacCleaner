import Testing
import SwiftUI
@testable import MyMacCleaner

// MARK: - Status Level Tests

@Suite("Status Level Tests")
struct StatusLevelTests {
    @Test("A value reaches a level only above its threshold")
    func thresholdsAreExclusive() {
        #expect(StatusLevel(0.5, warning: 0.5, critical: 0.8) == .normal)
        #expect(StatusLevel(0.51, warning: 0.5, critical: 0.8) == .warning)
        #expect(StatusLevel(0.8, warning: 0.5, critical: 0.8) == .warning)
        #expect(StatusLevel(0.81, warning: 0.5, critical: 0.8) == .critical)
    }

    @Test("CPU, memory and disk read their thresholds from Theme.Thresholds")
    func metricsUseThemeThresholds() {
        let cpu = Theme.Thresholds.CPU.self
        let memory = Theme.Thresholds.Memory.self
        let disk = Theme.Thresholds.DiskSpace.self

        #expect(StatusLevel.cpu(cpu.warningUsage) == .normal)
        #expect(StatusLevel.cpu(cpu.warningUsage + 0.01) == .warning)
        #expect(StatusLevel.cpu(cpu.criticalUsage + 0.01) == .critical)
        #expect(StatusLevel.memory(memory.warningUsage) == .normal)
        #expect(StatusLevel.memory(memory.warningUsage + 0.01) == .warning)
        #expect(StatusLevel.memory(memory.criticalUsage + 0.01) == .critical)
        #expect(StatusLevel.disk(disk.warningUsage) == .normal)
        #expect(StatusLevel.disk(disk.warningUsage + 0.01) == .warning)
        #expect(StatusLevel.disk(disk.criticalUsage + 0.01) == .critical)
    }

    @Test("At 85% memory every surface agrees: elevated, not critical")
    func memoryAgreesAcrossSurfaces() {
        #expect(StatusLevel.memory(0.85) == .warning)
        #expect(SystemHealthLevel.assess(diskUsage: 0, memoryUsage: 0.85) == .fair)
    }

    @Test("Levels use the semantic color tokens and carry their own icon and text")
    func levelsHaveTokenColorIconAndText() {
        let levels: [StatusLevel] = [.normal, .warning, .critical]

        #expect(levels.map(\.color) == [Theme.Colors.success, Theme.Colors.warning, Theme.Colors.error])
        #expect(Set(levels.map(\.icon)).count == levels.count)
        #expect(Set(levels.map(\.label)).count == levels.count)
        #expect(levels.allSatisfy { !$0.label.hasPrefix("common.") })
        #expect(StatusLevel.normal < .warning && StatusLevel.warning < .critical)
    }

    @Test("The Home health level shows the same color and icon as the status it stands for")
    func healthLevelMatchesStatusLevel() {
        #expect(SystemHealthLevel.healthy.color == StatusLevel.normal.color)
        #expect(SystemHealthLevel.fair.color == StatusLevel.warning.color)
        #expect(SystemHealthLevel.needsAttention.color == StatusLevel.critical.color)
        #expect(SystemHealthLevel.fair.icon == StatusLevel.warning.icon)
    }
}

// MARK: - Live Metric Source Tests

@Suite("Live Metric Source Tests")
struct LiveMetricSourceTests {
    @Test("Memory in use is sampled once, against physical memory")
    func memorySampleIsPlausible() throws {
        let sample = try #require(SystemStatsProvider.memoryUsage())

        #expect(sample.total == ProcessInfo.processInfo.physicalMemory)
        #expect(sample.used > 0)
        #expect(sample.used <= sample.total)
    }

    @Test("Disk use is read from the startup volume and carried in the stats the popover shows")
    func diskSampleIsPlausible() {
        let disk = SystemStatsProvider.diskUsage()
        let stats = SystemStats(diskUsed: disk.used, diskTotal: disk.total)

        #expect(disk.total > 0)
        #expect((0...disk.total).contains(disk.used))
        #expect((0.0...1.0).contains(stats.diskUsageFraction))
        #expect(SystemStats().diskUsageFraction == 0)
    }
}
