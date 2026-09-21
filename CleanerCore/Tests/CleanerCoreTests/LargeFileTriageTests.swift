import Testing
@testable import CleanerCore

@Suite("Large File Triage")
struct LargeFileTriageTests {
    @Test
    func acceptsOnlyCompletePersonalRegularFilesAtThreshold() throws {
        let triage = try LargeFileTriage(minimumLogicalBytes: 1_024)
        let accepted = try fixture(source: .userDownloads, logicalBytes: 1_024)
        let incomplete = try fixture(
            source: .userDesktop,
            logicalBytes: 2_048,
            completeness: .incomplete(reason: .unreadable)
        )
        let cache = try fixture(source: .userLibraryCaches, logicalBytes: 2_048)
        let directory = try fixture(source: .userDocuments, logicalBytes: 2_048, fileKind: .directory)
        let belowThreshold = try fixture(source: .userDocuments, logicalBytes: 1_023)

        let result = triage.evaluate([accepted, incomplete, cache, directory, belowThreshold])

        #expect(result.entries.count == 1)
        #expect(result.entries[0].revealIntent.locator == accepted.finding.locator)
        #expect(result.rejections == [
            .init(locator: incomplete.finding.locator, cause: .incompleteEvidence),
            .init(locator: cache.finding.locator, cause: .outsidePersonalContentRoots),
            .init(locator: directory.finding.locator, cause: .nonRegularFile),
            .init(locator: belowThreshold.finding.locator, cause: .belowThreshold),
        ])
    }

    @Test
    func ranksLogicalSizeThenLocatorAndKeepsAllMeasurementsIndependent() throws {
        let triage = try LargeFileTriage(minimumLogicalBytes: 1)
        let first = try fixture(
            source: .userDownloads,
            components: ["a.bin"],
            logicalBytes: 8_000,
            allocatedBytes: 1_024,
            sharedBytes: .unknown,
            conservativeBytes: .unavailable
        )
        let second = try fixture(
            source: .userDesktop,
            components: ["b.bin"],
            logicalBytes: 8_000,
            allocatedBytes: 4_096,
            sharedBytes: .observed(11),
            conservativeBytes: .observed(12)
        )
        let third = try fixture(
            source: .userDocuments,
            components: ["c.bin"],
            logicalBytes: 7_999
        )

        let entries = triage.evaluate([second, third, first]).entries

        #expect(entries.map(\.revealIntent.locator.components) == [["a.bin"], ["b.bin"], ["c.bin"]])
        #expect(entries[0].space.logicalBytes == .observed(8_000))
        #expect(entries[0].space.allocatedBytes == .observed(1_024))
        #expect(entries[0].space.sharedBytes == .unknown)
        #expect(entries[0].space.conservativeReclaimableBytes == .unavailable)
        #expect(entries[1].space.sharedBytes == .observed(11))
        #expect(entries[1].space.conservativeReclaimableBytes == .observed(12))
    }

    @Test
    func acceptedEntriesAreRevealOnlyAndCannotCarryCleanupState() throws {
        let triage = try LargeFileTriage(minimumLogicalBytes: 1)
        let finding = try fixture(source: .userDocuments, logicalBytes: 99)

        let entry = try #require(triage.evaluate([finding]).entries.first)

        #expect(entry.protection.content == .personalContent)
        #expect(entry.protection.inspection == .revealOnly)
        #expect(entry.protection.selection == .notPreselected)
        #expect(entry.protection.sizeDisposition == .notDisposableBySize)
        #expect(entry.revealIntent.declaredRootID == finding.finding.declaredRoot.id)
        #expect(entry.revealIntent.locator.rootID == finding.finding.declaredRoot.id)
    }

    @Test
    func revealIntentRejectsMismatchedDeclaredRoot() throws {
        let rootID = try DeclaredRootID("downloads")
        let otherRootID = try DeclaredRootID("documents")
        let locator = try RelativeLocator(rootID: rootID, components: ["file.bin"])

        #expect(throws: EvidenceValidationError.mismatchedRootIdentity) {
            try RevealIntent(declaredRootID: otherRootID, locator: locator)
        }
    }

    @Test
    func rejectsUnobservedLogicalSizeWithoutInventingMeasurements() throws {
        let triage = try LargeFileTriage(minimumLogicalBytes: 1)
        let finding = try fixture(
            source: .userDownloads,
            logicalBytes: nil,
            completeness: .complete
        )

        let result = triage.evaluate([finding])

        #expect(result.entries.isEmpty)
        #expect(result.rejections == [.init(locator: finding.finding.locator, cause: .unobservedLogicalSize)])
    }

    @Test
    func forgedNegativeOrMismatchedSpaceEvidenceIsRejectedBeforeRanking() throws {
        let triage = try LargeFileTriage(minimumLogicalBytes: 1)
        let negative = try fixture(
            source: .userDownloads,
            components: ["negative.bin"],
            logicalBytes: 1_024,
            spaceLogicalBytes: .observed(-1)
        )
        let mismatched = try fixture(
            source: .userDocuments,
            components: ["mismatched.bin"],
            logicalBytes: 1_024,
            spaceAllocatedBytes: .observed(9_999)
        )

        let result = triage.evaluate([negative, mismatched])

        #expect(result.entries.isEmpty)
        #expect(result.rejections == [
            .init(locator: negative.finding.locator, cause: .inconsistentSpaceEvidence),
            .init(locator: mismatched.finding.locator, cause: .inconsistentSpaceEvidence),
        ])
    }

    @Test
    func forgedScopeIdentityRootCategoryAndBoundaryEvidenceAreRejected() throws {
        let triage = try LargeFileTriage(minimumLogicalBytes: 1)
        let forgedDetector = try fixture(
            source: .userDownloads,
            components: ["forged-detector.bin"],
            logicalBytes: 1_024,
            detectorID: try DetectorID("forged.detector")
        )
        let forgedRoot = try fixture(
            source: .userDesktop,
            components: ["forged-root.bin"],
            logicalBytes: 1_024,
            declaredRootID: try DeclaredRootID("forged-root")
        )
        let forgedVersion = try fixture(
            source: .userDownloads,
            components: ["forged-version.bin"],
            logicalBytes: 1_024,
            detectorVersion: try DetectorVersion("9.9.9")
        )
        let forgedCategory = try fixture(
            source: .userDocuments,
            components: ["forged-category.bin"],
            logicalBytes: 1_024,
            category: .duplicate
        )
        let unsafeBoundary = try fixture(
            source: .userDownloads,
            components: ["forged-boundary.bin"],
            logicalBytes: 1_024,
            boundaries: .init(symlink: .unknown)
        )

        let result = triage.evaluate([
            forgedDetector,
            forgedRoot,
            forgedVersion,
            forgedCategory,
            unsafeBoundary,
        ])

        #expect(result.entries.isEmpty)
        #expect(result.rejections.map(\.cause) == Array(
            repeating: .untrustedScopeEvidence,
            count: 5
        ))
    }

    private func fixture(
        source: GeneralMacRootKind,
        components: [String] = ["file.bin"],
        logicalBytes: Int64?,
        allocatedBytes: Int64 = 4_096,
        sharedBytes: EvidenceValue<Int64> = .unknown,
        conservativeBytes: EvidenceValue<Int64> = .unknown,
        fileKind: FileKind = .regularFile,
        completeness: GeneralMacEvidenceCompleteness = .complete,
        spaceLogicalBytes: EvidenceValue<Int64>? = nil,
        spaceAllocatedBytes: EvidenceValue<Int64>? = nil,
        detectorID: DetectorID? = nil,
        detectorVersion: DetectorVersion? = nil,
        declaredRootID: DeclaredRootID? = nil,
        category: GeneralMacCategory? = nil,
        boundaries: BoundaryEvidence? = nil
    ) throws -> GeneralMacFinding {
        let catalog = GeneralMacScopeCatalog.current
        let registeredRoot = try catalog.declaredRoot(for: source)
        let registeredCategory = try catalog.registration(for: source).category
        let root = DeclaredRoot(id: declaredRootID ?? registeredRoot.id)
        let observation = try FileObservation(
            rootID: root.id,
            locator: .init(rootID: root.id, components: components),
            resourceIdentity: .observed(.init(device: 1, node: UInt64(components.joined().utf8.count))),
            sizes: .init(
                logicalBytes: logicalBytes.map(EvidenceValue.observed) ?? .unknown,
                allocatedBytes: .observed(allocatedBytes)
            ),
            modification: .observed(.init(unixNanoseconds: 1)),
            fileKind: fileKind,
            volume: .observed(try VolumeID("fixture-volume")),
            boundaries: boundaries ?? .init(
                symlink: .observed(false), alias: .observed(false), package: .observed(false),
                mount: .observed(false), protectedRoot: .observed(false), homeBoundary: .observed(false),
                externalVolume: .observed(false)
            )
        )
        let finding = try Finding(
            detectorID: detectorID ?? catalog.detectorID,
            detectorVersion: detectorVersion ?? catalog.version,
            provenance: .filesystemObservation,
            observation: observation,
            declaredRoot: root,
            observationInstant: .init(monotonicNanoseconds: 1)
        )
        return .init(
            finding: finding,
            category: category ?? registeredCategory,
            source: source,
            age: .unavailable,
            space: .init(
                logicalBytes: spaceLogicalBytes ?? observation.sizes.logicalBytes,
                allocatedBytes: spaceAllocatedBytes ?? observation.sizes.allocatedBytes,
                sharedBytes: sharedBytes,
                conservativeReclaimableBytes: conservativeBytes
            ),
            rebuildImpact: .reviewRequired,
            confidence: .observed,
            conservativeRisk: .reviewRequired,
            completeness: completeness
        )
    }
}
