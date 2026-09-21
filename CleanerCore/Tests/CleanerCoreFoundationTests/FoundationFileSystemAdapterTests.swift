import Foundation
import Testing
import CleanerCore
@testable import CleanerCoreFoundation

@Suite("CleanerCore Foundation FileSystem Adapter")
struct FoundationFileSystemAdapterTests {
    @Test
    func testOwnedRegularFileBecomesPureObservation() async throws {
        let fixture = try TemporaryFixture()
        let rootID = try DeclaredRootID("fixture-root")
        let fileURL = fixture.root.appendingPathComponent("model.bin")
        try Data([1, 2, 3, 4]).write(to: fileURL)
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [rootID: fixture.root],
            fileManager: FileManager()
        )

        let step = await adapter.nextObservation(
            after: nil,
            in: DeclaredRoot(id: rootID)
        )

        guard case let .observation(observation) = step else {
            Issue.record("Expected a real test-owned file observation.")
            return
        }
        #expect(observation.rootID == rootID)
        #expect(observation.locator.components == ["model.bin"])
        #expect(observation.sizes.logicalBytes == .observed(4))
        #expect(observation.sizes.allocatedBytes != .observed(0))
        #expect(observation.modification != .unknown)
        #expect(observation.fileKind == .regularFile)
        #expect(observation.resourceIdentity != .unavailable)
        #expect(observation.volume != .unavailable)
        #expect(observation.boundaries.symlink == .observed(false))
        #expect(observation.boundaries.package == .observed(false))
        #expect(observation.boundaries.mount == .observed(false))
    }

    @Test
    func missingDeclaredRootProducesTypedFaultWithoutHomeEnumeration() async throws {
        let fixture = try TemporaryFixture()
        let rootID = try DeclaredRootID("fixture-missing-root")
        let missingRoot = fixture.root.appendingPathComponent("missing")
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [rootID: missingRoot],
            fileManager: FileManager()
        )

        let step = await adapter.nextObservation(after: nil, in: DeclaredRoot(id: rootID))

        #expect(step == .terminal(.corruptMetadata))
        #expect(!missingRoot.path.hasPrefix(NSHomeDirectory()))
    }

    @Test
    func undeclaredRootIDFailsClosedWithoutEnumeratingKnownRoot() async throws {
        let fixture = try TemporaryFixture()
        let knownRootID = try DeclaredRootID("fixture-known-root")
        let requestedRootID = try DeclaredRootID("fixture-requested-root")
        try Data([1]).write(to: fixture.root.appendingPathComponent("kept.txt"))
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [knownRootID: fixture.root],
            fileManager: FileManager()
        )

        let step = await adapter.nextObservation(after: nil, in: DeclaredRoot(id: requestedRootID))

        #expect(step == .terminal(.unsupportedLayout))
    }

    @Test
    func cursorSelectsNextObservationWithinDeclaredRoot() async throws {
        let fixture = try TemporaryFixture()
        let rootID = try DeclaredRootID("fixture-cursor-root")
        try Data([1]).write(to: fixture.root.appendingPathComponent("a.txt"))
        try Data([2]).write(to: fixture.root.appendingPathComponent("b.txt"))
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [rootID: fixture.root],
            fileManager: FileManager()
        )

        let step = await adapter.nextObservation(
            after: ScanCursor(position: 1),
            in: DeclaredRoot(id: rootID)
        )

        guard case let .observation(observation) = step else {
            Issue.record("Expected the second declared-root observation.")
            return
        }
        #expect(observation.locator.components == ["b.txt"])
    }

    @Test
    func symlinkInsideRootIsReportedAsBoundaryAndNotTraversed() async throws {
        let fixture = try TemporaryFixture()
        let rootID = try DeclaredRootID("fixture-link-root")
        let outside = fixture.parent.appendingPathComponent("outside.txt")
        try Data([9]).write(to: outside)
        let link = fixture.root.appendingPathComponent("outside-link")
        try FileManager().createSymbolicLink(at: link, withDestinationURL: outside)
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [rootID: fixture.root],
            fileManager: FileManager()
        )

        let step = await adapter.nextObservation(after: nil, in: DeclaredRoot(id: rootID))

        guard case let .observation(observation) = step else {
            Issue.record("Expected the symlink itself to be observed as a boundary.")
            return
        }
        #expect(observation.locator.components == ["outside-link"])
        #expect(observation.boundaries.symlink == .observed(true))
        #expect(observation.fileKind == .symbolicLink)
    }

    @Test
    func packageDirectoryIsReportedAsBoundaryWithoutChildEnumeration() async throws {
        let fixture = try TemporaryFixture()
        let rootID = try DeclaredRootID("fixture-package-root")
        let package = fixture.root.appendingPathComponent("Demo.app")
        try FileManager().createDirectory(at: package, withIntermediateDirectories: true)
        try Data([7]).write(to: package.appendingPathComponent("nested.bin"))
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [rootID: fixture.root],
            fileManager: FileManager()
        )

        let first = await adapter.nextObservation(after: nil, in: DeclaredRoot(id: rootID))
        let second = await adapter.nextObservation(after: ScanCursor(position: 1), in: DeclaredRoot(id: rootID))

        guard case let .observation(observation) = first else {
            Issue.record("Expected the package directory itself to be observed.")
            return
        }
        #expect(observation.locator.components == ["Demo.app"])
        #expect(observation.fileKind == .package)
        #expect(observation.boundaries.package == .observed(true))
        #expect(second == .terminal(.complete))
    }

    @Test
    func emptyRootMapUsesCoreValidationError() {
        #expect(throws: ScanValidationError.emptyDeclaredRoots) {
            try FoundationFileSystemAdapter(declaredRoots: [:], fileManager: FileManager())
        }
    }

    @Test
    func malformedIdentityAttributesProduceTypedCorruptMetadata() async throws {
        let fixture = try TemporaryFixture()
        let rootID = try DeclaredRootID("fixture-malformed-root")
        try Data([1]).write(to: fixture.root.appendingPathComponent("bad.bin"))
        let adapter = try FoundationFileSystemAdapter(
            declaredRoots: [rootID: fixture.root],
            fileManager: MalformedAttributesFileManager()
        )

        let step = await adapter.nextObservation(after: nil, in: DeclaredRoot(id: rootID))

        #expect(step == .terminal(.corruptMetadata))
    }

    @Test
    func knownUnixDateUsesFileModificationEpochNanoseconds() {
        let timestamp = Date(timeIntervalSince1970: 1)

        let evidence = FoundationFileSystemAdapter.modificationEvidence(from: timestamp)

        #expect(evidence == .observed(.init(unixNanoseconds: 1_000_000_000)))
    }

    @Test
    func preEpochAndOutOfRangeDatesNeverTrapOrReinterpretTime() {
        let preEpoch = FoundationFileSystemAdapter.modificationEvidence(
            from: Date(timeIntervalSince1970: -1)
        )
        let outsideInt64Nanoseconds = FoundationFileSystemAdapter.modificationEvidence(
            from: Date(timeIntervalSince1970: 9_000_000_000)
        )

        #expect(preEpoch == .observed(.init(unixNanoseconds: -1_000_000_000)))
        #expect(outsideInt64Nanoseconds == .unavailable)
    }
}

private final class MalformedAttributesFileManager: FileManager, @unchecked Sendable {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        [
            .systemNumber: "not-a-device",
            .systemFileNumber: NSNumber(value: 10),
            .size: NSNumber(value: 1),
        ]
    }
}

private final class TemporaryFixture {
    let parent: URL
    let root: URL
    private let manager = FileManager()

    init() throws {
        parent = manager.temporaryDirectory
            .appendingPathComponent("mymaccleaner-foundation-tests")
            .appendingPathComponent(UUID().uuidString)
        root = parent.appendingPathComponent("root")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        do {
            try manager.removeItem(at: parent)
        } catch {
        }
    }
}
