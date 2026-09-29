import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreFoundation

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

    @Test
    func measuresOnlyTheDockerDiskImageAllocatedBytesWhenDockerIsPresent() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let image = home
            .appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
            .standardizedFileURL
        let measured = MeasuredPaths()
        let records = DeveloperInventoryAdapter(
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory: home,
            fileExists: { $0.lastPathComponent == "Docker.app" },
            fileAllocatedBytes: { url in
                measured.record(url.standardizedFileURL.path)
                return url.standardizedFileURL.path == image.path ? 52_280_905_728 : nil
            }
        ).observe()

        let docker = records.first { $0.tool == .docker }
        #expect(docker?.presence == .present)
        #expect(docker?.sizeBytes == 52_280_905_728)
        #expect(docker?.inventoryFact?.sizeBytes == 52_280_905_728)
        #expect(docker?.protection == .protectedSemanticOwner)
        #expect(measured.paths == [image.path])
    }

    @Test
    func dockerHasNoSizeWhenTheImageIsUnmeasurableOrDockerIsAbsent() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let denied = DeveloperInventoryAdapter(
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory: home,
            fileExists: { $0.lastPathComponent == "Docker.app" },
            fileAllocatedBytes: { _ in nil }
        ).observe().first { $0.tool == .docker }
        #expect(denied?.presence == .present)
        #expect(denied?.sizeBytes == nil)

        // Without Docker installed, its container is never touched.
        let measured = MeasuredPaths()
        let absent = DeveloperInventoryAdapter(
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory: home,
            fileExists: { _ in false },
            fileAllocatedBytes: { url in
                measured.record(url.path)
                return 1
            }
        ).observe().first { $0.tool == .docker }
        #expect(absent?.presence == .absent)
        #expect(absent?.sizeBytes == nil)
        #expect(measured.paths.isEmpty)
    }
}

/// Records which paths a measuring closure was asked about.
private final class MeasuredPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var paths: [String] { lock.withLock { recorded } }

    func record(_ path: String) { lock.withLock { recorded.append(path) } }
}
