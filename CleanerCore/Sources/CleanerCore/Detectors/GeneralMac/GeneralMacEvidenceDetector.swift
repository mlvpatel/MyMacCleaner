public struct GeneralMacEvidenceDetector: Sendable {
    public let scope: GeneralMacRootKind
    private let catalog: GeneralMacScopeCatalog

    public init(scope: GeneralMacRootKind, catalog: GeneralMacScopeCatalog = .current) {
        self.scope = scope
        self.catalog = catalog
    }

    public func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<GeneralMacFinding?, EvidenceValidationError> {
        do {
            let registration = try catalog.registration(for: scope)
            let root = try catalog.declaredRoot(for: scope)
            guard request.declaredRoots.contains(root), observation.rootID == root.id else {
                return .failure(.mismatchedRootIdentity)
            }
            let completeness = completeness(for: observation)
            guard observation.fileKind == .regularFile || isTopologyLeaf(completeness) else {
                return .success(nil)
            }
            let finding = try Finding(
                detectorID: catalog.detectorID,
                detectorVersion: catalog.version,
                provenance: .filesystemObservation,
                observation: observation,
                declaredRoot: root,
                observationInstant: clockReading.observationInstant
            )
            let category = category(for: registration, observation: observation)
            return .success(.init(
                finding: finding,
                category: category,
                source: scope,
                age: age(for: observation, observedAt: clockReading.wallClockInstant),
                space: space(for: observation),
                rebuildImpact: impact(for: category),
                confidence: confidence(for: observation),
                conservativeRisk: risk(for: category),
                completeness: completeness
            ))
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }

    private func category(
        for registration: GeneralMacScopeRegistration,
        observation: FileObservation
    ) -> GeneralMacCategory {
        if registration.rootKind == .userLibraryLogs,
           observation.locator.components.first == "DiagnosticReports" {
            return .crashReport
        }
        return registration.category
    }

    private func age(for observation: FileObservation, observedAt: WallClockInstant) -> GeneralMacAgeEvidence {
        if case let .observed(modification) = observation.modification {
            return .observed(modification: modification, observedAt: observedAt)
        }
        return .unavailable
    }

    private func space(for observation: FileObservation) -> SpaceEvidenceVector {
        guard observation.linkCount == .observed(1) else {
            return .init(
                logicalBytes: observation.sizes.logicalBytes,
                allocatedBytes: observation.sizes.allocatedBytes
            )
        }
        return .init(
            logicalBytes: observation.sizes.logicalBytes,
            allocatedBytes: observation.sizes.allocatedBytes,
            sharedBytes: .observed(0),
            conservativeReclaimableBytes: observation.sizes.allocatedBytes
        )
    }

    private func impact(for category: GeneralMacCategory) -> RebuildImpact {
        switch category {
        case .cache, .temporary: return .rebuildable
        case .log, .crashReport, .largeFile, .duplicate: return .reviewRequired
        }
    }

    private func risk(for category: GeneralMacCategory) -> ConservativeRisk {
        switch category {
        case .cache, .temporary: return .low
        case .log, .crashReport, .largeFile, .duplicate: return .reviewRequired
        }
    }

    private func confidence(for observation: FileObservation) -> EvidenceConfidence {
        switch (observation.sizes.logicalBytes, observation.sizes.allocatedBytes, observation.modification) {
        case (.observed, .observed, .observed): return .observed
        case (.unavailable, _, _), (_, .unavailable, _), (_, _, .unavailable): return .unavailable
        default: return .partial
        }
    }

    private func completeness(for observation: FileObservation) -> GeneralMacEvidenceCompleteness {
        if observation.boundaries.package == .observed(true) { return .incomplete(reason: .package) }
        if observation.boundaries.symlink == .observed(true) { return .incomplete(reason: .symbolicLink) }
        if observation.boundaries.alias == .observed(true) { return .incomplete(reason: .alias) }
        if observation.boundaries.mount == .observed(true) { return .incomplete(reason: .mount) }
        if observation.boundaries.protectedRoot == .observed(true) { return .incomplete(reason: .protectedRoot) }
        if observation.boundaries.homeBoundary == .observed(true) { return .incomplete(reason: .nestedHome) }
        if observation.boundaries.externalVolume == .observed(true) { return .incomplete(reason: .volumeChanged) }
        guard isObserved(observation.resourceIdentity),
              isObserved(observation.volume),
              isObserved(observation.sizes.logicalBytes),
              isObserved(observation.sizes.allocatedBytes),
              isObserved(observation.modification),
              areObservedBoundaryFacts(observation.boundaries) else {
            return .incomplete(reason: .unavailableMetadata)
        }
        return .complete
    }

    private func isObserved<Value>(_ value: EvidenceValue<Value>) -> Bool where Value: Sendable {
        if case .observed = value { return true }
        return false
    }

    private func areObservedBoundaryFacts(_ boundaries: BoundaryEvidence) -> Bool {
        [boundaries.symlink, boundaries.alias, boundaries.package, boundaries.mount,
         boundaries.protectedRoot, boundaries.homeBoundary, boundaries.externalVolume]
            .allSatisfy(isObserved)
    }

    private func isTopologyLeaf(_ completeness: GeneralMacEvidenceCompleteness) -> Bool {
        guard case let .incomplete(reason) = completeness else {
            return false
        }
        switch reason {
        case .package,
             .symbolicLink,
             .alias,
             .mount,
             .volumeChanged,
             .nestedHome,
             .protectedRoot,
             .unreadable,
             .unavailableMetadata:
            return true
        }
    }
}

struct GeneralMacRegistryDetector: LocalDetector {
    let catalog: GeneralMacScopeCatalog

    var identifier: DetectorID { catalog.detectorID }
    var version: DetectorVersion { catalog.version }

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        do {
            let scope = try catalog.rootKind(for: observation.rootID)
            return GeneralMacEvidenceDetector(scope: scope, catalog: catalog)
                .makeFinding(from: observation, request: request, clockReading: clockReading)
                .map { $0?.finding }
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}

extension GeneralMacScopeCatalog {
    var detectorRegistration: DetectorRegistration {
        .init(detector: GeneralMacRegistryDetector(catalog: self))
    }
}
