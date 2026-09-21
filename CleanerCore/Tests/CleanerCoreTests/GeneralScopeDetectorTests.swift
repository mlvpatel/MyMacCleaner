import Testing
@testable import CleanerCore

@Suite("General Mac Scope Detector")
struct GeneralScopeDetectorTests {
    @Test
    func shippedCatalogContainsOnlySixDeterministicRoots() {
        let catalog = GeneralMacScopeCatalog.current

        #expect(catalog.version.value == "1.0.0")
        #expect(catalog.detectorID.value == "general.mac.storage")
        #expect(catalog.registrations.map(\.id.value) == [
            "user-library-caches",
            "user-library-logs",
            "user-temporary",
            "user-downloads",
            "user-desktop",
            "user-documents",
        ])
        #expect(catalog.limits.maximumDepth == 8)
        #expect(catalog.limits.maximumEntriesPerRoot == 25_000)
        #expect(catalog.limits.maximumFindingsPerRoot == 10_000)
        #expect(catalog.limits.maximumObservedLogicalBytesPerRoot == 1_099_511_627_776)
        #expect(catalog.limits.maximumFindingsPerBatch == 128)
        #expect(catalog.limits.maximumRootsPerRequest == 6)
    }

    @Test
    func cacheAndCrashEvidenceRemainTypedAndIndependent() throws {
        let catalog = GeneralMacScopeCatalog.current
        let logsRoot = try catalog.declaredRoot(for: .userLibraryLogs)
        let observation = try FileObservation(
            rootID: logsRoot.id,
            locator: .init(rootID: logsRoot.id, components: ["DiagnosticReports", "example.crash"]),
            resourceIdentity: .observed(.init(device: 1, node: 2)),
            sizes: .init(logicalBytes: .observed(4), allocatedBytes: .unknown),
            modification: .observed(.init(unixNanoseconds: 1)),
            fileKind: .regularFile,
            volume: .observed(try VolumeID("volume:fixture")),
            boundaries: .init(
                symlink: .observed(false),
                alias: .observed(false),
                package: .observed(false),
                mount: .observed(false),
                protectedRoot: .observed(false),
                homeBoundary: .observed(false),
                externalVolume: .observed(false)
            )
        )
        let result = GeneralMacEvidenceDetector(scope: .userLibraryLogs)
            .makeFinding(
                from: observation,
                request: try catalog.scanRequest(for: [.userLibraryLogs]),
                clockReading: .init(
                    observationInstant: .init(monotonicNanoseconds: 2),
                    wallClockInstant: .init(unixNanoseconds: 3)
                )
            )
        let finding = try #require(try result.get())

        #expect(finding.category == .crashReport)
        #expect(finding.space.logicalBytes == .observed(4))
        #expect(finding.space.allocatedBytes == .unknown)
        #expect(finding.space.sharedBytes == .unknown)
        #expect(finding.completeness == .incomplete(reason: .unavailableMetadata))
        #expect(finding.finding.observationInstant == .init(monotonicNanoseconds: 2))
        #expect(finding.age == .observed(
            modification: .init(unixNanoseconds: 1),
            observedAt: .init(unixNanoseconds: 3)
        ))
    }

    @Test
    func topologyAndUnavailableMetadataCannotBecomeComplete() throws {
        let catalog = GeneralMacScopeCatalog.current
        let root = try catalog.declaredRoot(for: .userLibraryCaches)
        let request = try catalog.scanRequest(for: [.userLibraryCaches])
        let cases: [(BoundaryEvidence, EvidenceValue<FileIdentityEvidence>, GeneralMacEvidenceCompleteness)] = [
            (.init(symlink: .observed(true)), .observed(.init(device: 1, node: 1)), .incomplete(reason: .symbolicLink)),
            (.init(symlink: .observed(false), alias: .observed(true)), .observed(.init(device: 1, node: 1)), .incomplete(reason: .alias)),
            (.init(symlink: .observed(false), package: .observed(true)), .observed(.init(device: 1, node: 1)), .incomplete(reason: .package)),
            (.init(symlink: .observed(false), mount: .observed(true)), .observed(.init(device: 1, node: 1)), .incomplete(reason: .mount)),
            (.init(symlink: .observed(false), externalVolume: .observed(true)), .observed(.init(device: 1, node: 1)), .incomplete(reason: .volumeChanged)),
            (.init(symlink: .observed(false)), .unavailable, .incomplete(reason: .unavailableMetadata)),
        ]

        for (boundaries, identity, expected) in cases {
            let observation = try FileObservation(
                rootID: root.id,
                locator: .init(rootID: root.id, components: ["entry.bin"]),
                resourceIdentity: identity,
                sizes: .init(logicalBytes: .observed(1), allocatedBytes: .observed(1)),
                modification: .observed(.init(unixNanoseconds: 1)),
                fileKind: .regularFile,
                volume: .observed(try VolumeID("volume:fixture")),
                boundaries: boundaries
            )
            let finding = try #require(try GeneralMacEvidenceDetector(scope: .userLibraryCaches)
                .makeFinding(
                    from: observation,
                    request: request,
                    clockReading: .init(
                        observationInstant: .init(monotonicNanoseconds: 2),
                        wallClockInstant: .init(unixNanoseconds: 3)
                    )
                )
                .get())
            #expect(finding.completeness == expected)
        }
    }

    @Test
    func duplicateAndOversizedScopeSelectionsFailBeforeARequestExists() throws {
        let catalog = GeneralMacScopeCatalog.current

        #expect(throws: GeneralMacScopeCatalogError.duplicateScope) {
            try catalog.scanRequest(for: [.userLibraryCaches, .userLibraryCaches])
        }
        #expect(throws: GeneralMacScopeCatalogError.tooManyRoots) {
            try catalog.scanRequest(for: [
                .userLibraryCaches, .userLibraryLogs, .userTemporary,
                .userDownloads, .userDesktop, .userDocuments, .userLibraryCaches,
            ])
        }
    }

    @Test
    func scanRequestUsesTheFixedPerRootAndBatchBudgets() throws {
        let request = try GeneralMacScopeCatalog.current.scanRequest(for: [.userLibraryCaches])

        #expect(request.budget.maximumFindings == 128)
        #expect(request.budget.maximumObservations == 128)
        #expect(request.budget.maximumDepth == 8)
        #expect(request.budget.maximumEntriesPerRoot == 25_000)
        #expect(request.budget.maximumBatches == 1_200)
        #expect(request.budget.maximumObservedBytesPerRoot == 1_099_511_627_776)
        #expect(request.budget.maximumFindingsPerRoot == 10_000)
        #expect(request.budget.maximumRootsPerRequest == 6)
    }
}
