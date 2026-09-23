import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Docker Disk Usage Adapter")
struct DockerDiskUsageAdapterTests {
    @Test
    func presenceOnlyNeverLaunchesAProcess() {
        let adapter = DockerDiskUsageAdapter()
        #expect(adapter.mode == .presenceOnly)
        let record = adapter.snapshot(presence: .present)
        #expect(record.tool == .docker)
        #expect(record.presence == .present)
        #expect(record.protection == .protectedSemanticOwner)
        #expect(record.inventoryFact != nil)
    }
}

@Suite("Developer Inventory Adapter")
struct DeveloperInventoryAdapterTests {
    @Test
    func observesApplicationsWithoutHomebrewProbing() {
        let records = DeveloperInventoryAdapter(
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true),
            fileExists: { $0.lastPathComponent == "Cursor.app" }
        ).observe()
        let byTool = Dictionary(uniqueKeysWithValues: records.map { ($0.tool, $0.presence) })
        #expect(byTool[.cursor] == .present)
        #expect(byTool[.vscode] == .absent)
        #expect(byTool[.docker] == .absent)
        #expect(byTool[.homebrew] == .unavailable)
        #expect(records.allSatisfy { $0.protection == .protectedSemanticOwner })
    }

    @Test
    func sizesPresentDotfileRootsContentBlindWithoutBecomingCandidates() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
        let records = DeveloperInventoryAdapter(
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory: home,
            fileExists: { $0.standardizedFileURL.path == claude.path },
            directoryAllocatedBytes: { url in
                url.standardizedFileURL.path == claude.path ? 4_096 : nil
            }
        ).observe()

        let claudeRecord = records.first { $0.tool == .claudeConfig }
        #expect(claudeRecord?.presence == .present)
        #expect(claudeRecord?.sizeBytes == 4_096)
        #expect(claudeRecord?.protection == .protectedSemanticOwner)
        #expect(claudeRecord?.inventoryFact?.sizeBytes == 4_096)

        // An absent dotfile carries no size and stays inventory-only.
        let codex = records.first { $0.tool == .codex }
        #expect(codex?.presence == .absent)
        #expect(codex?.sizeBytes == nil)
    }
}
