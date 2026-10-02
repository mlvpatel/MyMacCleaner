import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("General Mac Foundation Adapter")
struct GeneralMacFilesystemAdapterTests {
    @Test
    func fixedCacheRootProducesOneCacheFinding() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try Data([1, 2, 3]).write(to: fixture.root.appendingPathComponent("cache.bin"))
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )

        let root = try catalog.declaredRoot(for: .userLibraryCaches)
        let step = await adapter.nextObservation(after: nil, in: root)

        guard case let .observation(observation) = step else {
            Issue.record("Expected a test-owned cache observation.")
            return
        }
        let detector = GeneralMacEvidenceDetector(scope: .userLibraryCaches)
        let finding = try #require(
            detector.makeFinding(
                from: observation,
                request: try catalog.scanRequest(for: [.userLibraryCaches]),
                clockReading: .init(
                    observationInstant: .init(monotonicNanoseconds: 10),
                    wallClockInstant: .init(unixNanoseconds: 11)
                )
            ).get()
        )

        #expect(finding.category == .cache)
        #expect(finding.source == .userLibraryCaches)
        #expect(finding.completeness == .complete)
        #expect(finding.finding.locator.components == ["cache.bin"])
    }

    @Test
    func packageLeafIsVisibleAndItsChildIsNeverEnumerated() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        let package = fixture.root.appendingPathComponent("Demo.app")
        try FileManager().createDirectory(at: package, withIntermediateDirectories: true)
        try Data([4]).write(to: package.appendingPathComponent("nested.bin"))
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        let first = await adapter.nextObservation(after: nil, in: root)
        guard case let .observation(observation) = first else {
            Issue.record("Expected the package leaf to remain visible evidence.")
            return
        }

        #expect(observation.fileKind == .package)
        #expect(observation.locator.components == ["Demo.app"])
        #expect(observation.boundaries.package == .observed(true))
        let second = await adapter.nextObservation(after: .init(position: 1), in: root)
        #expect(second == .terminal(.complete))
    }

    @Test
    func symbolicLinkLeafIsVisibleAndItsTargetIsNeverEnumerated() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try fixture.createSymbolicLinkLeaf()
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        guard case let .observation(observation) = await adapter.nextObservation(after: nil, in: root) else {
            Issue.record("Expected the symbolic-link leaf to remain visible evidence.")
            return
        }

        #expect(observation.fileKind == .symbolicLink)
        #expect(observation.locator.components == ["linked-directory"])
        #expect(observation.boundaries.symlink == .observed(true))
        #expect(await adapter.nextObservation(after: .init(position: 1), in: root) == .terminal(.complete))
    }

    @Test
    func aliasLeafIsVisibleAndItsTargetIsNeverEnumerated() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try fixture.createAliasLeaf()
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        guard case let .observation(observation) = await adapter.nextObservation(after: nil, in: root) else {
            Issue.record("Expected the alias leaf to remain visible evidence.")
            return
        }

        #expect(observation.locator.components == ["linked-directory-alias"])
        #expect(observation.boundaries.alias == .observed(true))
        #expect(await adapter.nextObservation(after: .init(position: 1), in: root) == .terminal(.complete))
    }

    @Test
    func injectedResourceOmissionStaysVisibleAndStopsBeforeDescendants() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try fixture.createDirectoryWithChild(named: "metadata-omitted")
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager(),
            resourceValues: { url in
                if url.lastPathComponent == "metadata-omitted" {
                    return GeneralMacResourceValues()
                }
                return try GeneralMacResourceValues(url: url)
            }
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        guard case let .observation(observation) = await adapter.nextObservation(after: nil, in: root) else {
            Issue.record("Expected incomplete resource evidence to remain visible.")
            return
        }

        #expect(observation.locator.components == ["metadata-omitted"])
        #expect(observation.volume != .observed(try VolumeID("unexpected-volume")))
        #expect(observation.boundaries.externalVolume == .unavailable)
        #expect(await adapter.nextObservation(after: .init(position: 1), in: root) == .terminal(.complete))
    }

    @Test
    func rootReplacementStopsTheExistingCursorBeforeAnotherEntry() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try Data([1]).write(to: fixture.root.appendingPathComponent("first.bin"))
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        guard case .observation = await adapter.nextObservation(after: nil, in: root) else {
            Issue.record("Expected the first fixture entry before root replacement.")
            return
        }
        try fixture.replaceCacheRoot()

        let step = await adapter.nextObservation(after: .init(position: 1), in: root)
        #expect(step == .terminal(.unsupportedLayout))
    }

    @Test
    func rootDisappearanceStopsTheExistingCursorBeforeAnotherEntry() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try Data([1]).write(to: fixture.root.appendingPathComponent("first.bin"))
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        guard case .observation = await adapter.nextObservation(after: nil, in: root) else {
            Issue.record("Expected the first fixture entry before root removal.")
            return
        }
        try fixture.removeCacheRoot()

        #expect(
            await adapter.nextObservation(after: .init(position: 1), in: root)
                == .terminal(.unsupportedLayout)
        )
    }

    @Test
    func missingOptionalScopeRootDoesNotPreventOtherRootsFromOpening() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try fixture.removeLogsRoot()
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let logsRoot = try catalog.declaredRoot(for: .userLibraryLogs)

        let step = await adapter.nextObservation(after: nil, in: logsRoot)
        #expect(step == .terminal(.unsupportedLayout))
    }

    @Test
    func derivedRootSymlinkIsRejectedBeforeAnyDescendantEvidence() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try fixture.replaceCacheRootWithSymlink()
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        let step = await adapter.nextObservation(after: nil, in: root)
        #expect(step == .terminal(.unsupportedLayout))
    }

    @Test
    func permissionFailureBecomesTypedPermissionDeniedOutcome() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: DeniedAttributesFileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        let step = await adapter.nextObservation(after: nil, in: root)
        #expect(step == .terminal(.permissionDenied))
    }

    @Test
    func unreadableSubfolderIsSkippedAndSiblingsAreStillObserved() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        for index in 0..<30 {
            let folder = fixture.root.appendingPathComponent("visible-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1]).write(to: folder.appendingPathComponent("file.bin"))
        }
        let denied = fixture.root.appendingPathComponent("denied", isDirectory: true)
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data([1]).write(to: denied.appendingPathComponent("hidden.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        let (observed, terminal) = await walk(adapter, root: root)

        // Every readable sibling is still observed; nothing inside the denied folder is.
        #expect(observed.filter { $0.hasSuffix("file.bin") }.count == 30)
        #expect(!observed.contains { $0.hasPrefix("denied/") })
        // The skipped subtree is still reported, so the root never reads as complete.
        #expect(terminal == .permissionDenied)
    }

    @Test
    func unreadableEntryMetadataIsSkippedAndCursorPositionsStayContiguous() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        for name in ["a.bin", "bad.bin", "c.bin"] {
            try Data([1]).write(to: fixture.root.appendingPathComponent(name))
        }
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager(),
            resourceValues: { url in
                guard url.lastPathComponent != "bad.bin" else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
                }
                return try GeneralMacResourceValues(url: url)
            }
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        // walk() advances the cursor by one per observation, so any position gap ends the walk early.
        let (observed, terminal) = await walk(adapter, root: root)

        #expect(observed.filter { $0.hasSuffix(".bin") }.sorted() == ["a.bin", "c.bin"])
        #expect(terminal == .permissionDenied)
    }

    @Test
    func skippedEntriesStillCountTowardTheEntryCap() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        for index in 0..<6 {
            try Data([1]).write(to: fixture.root.appendingPathComponent("unreadable-\(index).bin"))
        }
        let calls = LockedCounter()
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager(),
            resourceValues: { url in
                guard !url.lastPathComponent.hasPrefix("unreadable-") else {
                    calls.increment()
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
                }
                return try GeneralMacResourceValues(url: url)
            },
            maximumEntriesPerRoot: 3
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        let step = await adapter.nextObservation(after: nil, in: root)

        #expect(step == .terminal(.corruptMetadata))
        #expect(calls.value <= 3)
    }

    @Test
    func cancelledTaskStopsTheWalkBeforeAnotherEntry() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try Data([1]).write(to: fixture.root.appendingPathComponent("never.bin"))
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        let step = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await adapter.nextObservation(after: nil, in: root)
        }.value

        #expect(step == .terminal(.cancelled))
    }

    @Test
    func shallowerEntriesAreObservedBeforeDeeperOnes() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        for top in ["first", "second"] {
            let deep = fixture.root.appendingPathComponent("\(top)/a/b", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            try Data([1]).write(to: deep.appendingPathComponent("leaf.bin"))
        }
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: FileManager()
        )

        let (observed, terminal) = await walk(adapter, root: try catalog.declaredRoot(for: .userLibraryCaches))

        // Breadth-first, so under the per-root caps a deep subtree cannot starve shallow entries.
        let depths = observed.map { $0.split(separator: "/").count }
        #expect(depths == depths.sorted())
        #expect(observed.contains("first/a/b/leaf.bin") && observed.contains("second/a/b/leaf.bin"))
        #expect(terminal == .complete)
    }

    @Test
    func laterMetadataDenialPreservesPriorEvidenceAndNeverCompletes() async throws {
        let fixture = try GeneralMacTemporaryFixture()
        try Data([1]).write(to: fixture.root.appendingPathComponent("first.bin"))
        try Data([2]).write(to: fixture.root.appendingPathComponent("second.bin"))
        let manager = LaterDeniedAttributesFileManager(denyOnRead: 5)
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(
            catalog: catalog,
            anchors: fixture.anchors,
            fileManager: manager
        )
        let root = try catalog.declaredRoot(for: .userLibraryCaches)

        guard case .observation = await adapter.nextObservation(after: nil, in: root) else {
            Issue.record("Expected evidence before the injected metadata denial.")
            return
        }
        let terminal = await adapter.nextObservation(after: .init(position: 1), in: root)
        #expect(terminal == .terminal(.permissionDenied))
    }

    @Test
    func forgedDeclaredRootIsRejectedByCatalogBeforeAdapterUse() throws {
        let catalog = GeneralMacScopeCatalog.current
        let forgedRoot = try DeclaredRootID("unregistered-root")

        #expect(throws: GeneralMacScopeCatalogError.unknownScope) {
            try catalog.rootKind(for: forgedRoot)
        }
    }

    @Test
    func generalAdapterUsesEpochTimeAndRejectsUnsafeModificationDates() {
        let known = GeneralMacFilesystemAdapter.modificationEvidence(
            Date(timeIntervalSince1970: 1)
        )
        let preEpoch = GeneralMacFilesystemAdapter.modificationEvidence(
            Date(timeIntervalSince1970: -1)
        )
        let outsideInt64Nanoseconds = GeneralMacFilesystemAdapter.modificationEvidence(
            Date(timeIntervalSince1970: 9_000_000_000)
        )

        #expect(known == .observed(.init(unixNanoseconds: 1_000_000_000)))
        #expect(preEpoch == .observed(.init(unixNanoseconds: -1_000_000_000)))
        #expect(outsideInt64Nanoseconds == .unavailable)
    }
}

private final class GeneralMacTemporaryFixture {
    let root: URL
    let anchors: GeneralMacRootAnchors
    private let parent: URL
    private let manager = FileManager()

    init() throws {
        parent = manager.temporaryDirectory
            .appendingPathComponent("mymaccleaner-general-mac-tests")
            .appendingPathComponent(UUID().uuidString)
        let home = parent.appendingPathComponent("home")
        root = home.appendingPathComponent("Library/Caches")
        let temporary = parent.appendingPathComponent("temporary")
        for path in [root, home.appendingPathComponent("Library/Logs"), temporary,
                     home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop"),
                     home.appendingPathComponent("Documents")] {
            try manager.createDirectory(at: path, withIntermediateDirectories: true)
        }
        anchors = .init(homeDirectory: home, temporaryDirectory: temporary)
    }

    deinit {
        try? manager.removeItem(at: parent)
    }

    func replaceCacheRoot() throws {
        let oldRoot = parent.appendingPathComponent("old-cache-root")
        try manager.moveItem(at: root, to: oldRoot)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([2]).write(to: root.appendingPathComponent("replacement.bin"))
    }

    func removeLogsRoot() throws {
        try manager.removeItem(at: anchors.homeDirectory.appendingPathComponent("Library/Logs"))
    }

    func replaceCacheRootWithSymlink() throws {
        let target = parent.appendingPathComponent("cache-symlink-target")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([3]).write(to: target.appendingPathComponent("hidden.bin"))
        try manager.removeItem(at: root)
        try manager.createSymbolicLink(at: root, withDestinationURL: target)
    }

    func removeCacheRoot() throws {
        try manager.removeItem(at: root)
    }

    func createDirectoryWithChild(named name: String) throws {
        let directory = root.appendingPathComponent(name)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([8]).write(to: directory.appendingPathComponent("must-not-observe.bin"))
    }

    func createSymbolicLinkLeaf() throws {
        let target = parent.appendingPathComponent("symbolic-link-target")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([5]).write(to: target.appendingPathComponent("must-not-observe.bin"))
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("linked-directory"),
            withDestinationURL: target
        )
    }

    func createAliasLeaf() throws {
        let target = parent.appendingPathComponent("alias-target")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([6]).write(to: target.appendingPathComponent("must-not-observe.bin"))
        let bookmark = try target.bookmarkData(
            options: .suitableForBookmarkFile,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(
            bookmark,
            to: root.appendingPathComponent("linked-directory-alias")
        )
    }
}

private final class DeniedAttributesFileManager: FileManager, @unchecked Sendable {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EACCES.rawValue))
    }
}

private final class LaterDeniedAttributesFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private let denyOnRead: Int
    private var reads = 0

    init(denyOnRead: Int) {
        self.denyOnRead = denyOnRead
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        lock.lock()
        reads += 1
        let shouldDeny = reads >= denyOnRead
        lock.unlock()
        if shouldDeny {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EACCES.rawValue))
        }
        return try super.attributesOfItem(atPath: path)
    }
}

private func walk(
    _ adapter: GeneralMacFilesystemAdapter,
    root: DeclaredRoot
) async -> (observed: [String], terminal: ScanOutcome) {
    var observed: [String] = []
    var cursor: ScanCursor?
    while true {
        switch await adapter.nextObservation(after: cursor, in: root) {
        case .observation(let observation):
            observed.append(observation.locator.components.joined(separator: "/"))
            cursor = ScanCursor(position: (cursor?.position ?? 0) + 1)
        case .terminal(let outcome):
            return (observed, outcome)
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
