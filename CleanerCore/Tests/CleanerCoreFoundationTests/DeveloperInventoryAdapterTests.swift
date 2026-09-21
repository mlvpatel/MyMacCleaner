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
            fileExists: { $0.lastPathComponent == "Cursor.app" }
        ).observe()
        let byTool = Dictionary(uniqueKeysWithValues: records.map { ($0.tool, $0.presence) })
        #expect(byTool[.cursor] == .present)
        #expect(byTool[.vscode] == .absent)
        #expect(byTool[.docker] == .absent)
        #expect(byTool[.homebrew] == .unavailable)
        #expect(records.allSatisfy { $0.protection == .protectedSemanticOwner })
    }
}
