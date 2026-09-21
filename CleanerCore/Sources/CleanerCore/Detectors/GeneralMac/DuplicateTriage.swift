public enum CloneShareUncertainty: String, Equatable, Sendable {
    case unknown
}

public struct DuplicateContentMember: Equatable, Sendable {
    public let declaredRootID: DeclaredRootID
    public let locator: RelativeLocator

    public init(declaredRootID: DeclaredRootID, locator: RelativeLocator) throws {
        guard declaredRootID == locator.rootID else {
            throw EvidenceValidationError.mismatchedRootIdentity
        }
        self.declaredRootID = declaredRootID
        self.locator = locator
    }

    init(validatedDeclaredRootID: DeclaredRootID, locator: RelativeLocator) {
        declaredRootID = validatedDeclaredRootID
        self.locator = locator
    }
}

public struct DuplicateResourceMember: Equatable, Sendable {
    public let resource: ContentResourceIdentity
    public let members: [DuplicateContentMember]
    public let space: SpaceEvidenceVector

    public init(
        resource: ContentResourceIdentity,
        members: [DuplicateContentMember],
        space: SpaceEvidenceVector
    ) {
        self.resource = resource
        self.members = members
        self.space = space
    }
}

public struct DuplicateGroup: Equatable, Sendable {
    public let resources: [DuplicateResourceMember]
    public let cloneShareUncertainty: CloneShareUncertainty

    public init(resources: [DuplicateResourceMember]) {
        self.resources = resources
        cloneShareUncertainty = .unknown
    }
}

public enum DuplicateTriageUnresolvedCause: Equatable, Sendable {
    case untrustedScopeEvidence
    case incompleteEvidence
    case unavailableResourceIdentity
    case unobservedLogicalSize
    case conflictingResourceEvidence
    case contentEvidenceUnavailable(ContentEvidenceOutcomeCode)
    case candidateLimitExceeded
}

public struct DuplicateTriageUnresolved: Equatable, Sendable {
    public let members: [DuplicateContentMember]
    public let cause: DuplicateTriageUnresolvedCause

    public init(members: [DuplicateContentMember], cause: DuplicateTriageUnresolvedCause) {
        self.members = members
        self.cause = cause
    }
}

public struct DuplicateTriageResult: Equatable, Sendable {
    public let groups: [DuplicateGroup]
    public let unresolved: [DuplicateTriageUnresolved]

    public init(groups: [DuplicateGroup], unresolved: [DuplicateTriageUnresolved]) {
        self.groups = groups
        self.unresolved = unresolved
    }
}

public struct DuplicateTriage: Sendable {
    private let contentEvidence: any ContentEvidencePort

    public init(contentEvidence: any ContentEvidencePort) {
        self.contentEvidence = contentEvidence
    }

    public func evaluate(_ findings: [GeneralMacFinding]) async -> DuplicateTriageResult {
        let partition = partitionResources(findings)
        var unresolved = partition.unresolved
        var groups: [DuplicateGroup] = []
        var remainingCandidates = ContentReadLimits.current.maximumCandidatesPerScan
        var remainingBytes = ContentReadLimits.current.maximumBytesPerScan
        let contentSession = await contentEvidence.beginSession(limits: .current)

        candidateSets: for logicalSize in partition.resourcesByLogicalSize.keys.sorted(by: >) {
            guard let candidates = partition.resourcesByLogicalSize[logicalSize] else { continue }
            guard candidates.count > 1 else { continue }
            guard candidates.count <= remainingCandidates else {
                unresolved.append(.init(
                    members: Self.members(in: candidates),
                    cause: .candidateLimitExceeded
                ))
                continue
            }

            guard let requestedBytes = Self.checkedRequestedBytes(for: candidates),
                  requestedBytes <= remainingBytes,
                  candidates.allSatisfy({ Self.logicalBytes(of: $0) <= ContentReadLimits.current.maximumBytesPerFile }) else {
                unresolved.append(.init(
                    members: Self.members(in: candidates),
                    cause: .contentEvidenceUnavailable(.budgetExceeded)
                ))
                continue
            }
            let limits: ContentReadLimits
            do {
                limits = try .init(
                    maximumCandidatesPerScan: remainingCandidates,
                    maximumChunkBytes: ContentReadLimits.current.maximumChunkBytes,
                    maximumBytesPerFile: ContentReadLimits.current.maximumBytesPerFile,
                    maximumBytesPerScan: remainingBytes
                )
            } catch {
                unresolved.append(.init(
                    members: Self.members(in: candidates),
                    cause: .contentEvidenceUnavailable(.budgetExceeded)
                ))
                continue
            }
            remainingCandidates -= candidates.count
            remainingBytes -= requestedBytes

            let contentResult = await contentEvidence(
                for: candidates,
                limits: limits,
                session: contentSession
            )
            switch contentResult {
            case let .complete(digests):
                for digestMembers in digests.values where digestMembers.count > 1 {
                    groups.append(.init(resources: digestMembers.sorted(by: Self.resourcePrecedes)))
                }
            case let .unresolved(cause):
                unresolved.append(.init(
                    members: Self.members(in: candidates),
                    cause: .contentEvidenceUnavailable(cause)
                ))
                if cause == .cancelled {
                    break candidateSets
                }
            }
        }

        return .init(
            groups: groups.sorted(by: Self.groupPrecedes),
            unresolved: unresolved.sorted(by: Self.unresolvedPrecedes)
        )
    }

    private func contentEvidence(
        for resources: [DuplicateResourceMember],
        limits: ContentReadLimits,
        session: any ContentEvidenceSession
    ) async -> ContentCollectionResult {
        var digests: [ContentDigest: [DuplicateResourceMember]] = [:]
        for resource in resources.sorted(by: Self.resourcePrecedes) {
            guard let member = resource.members.first else { continue }
            let request: ContentEvidenceRequest
            do {
                request = try .init(
                    declaredRootID: member.declaredRootID,
                    locator: member.locator,
                    resource: resource.resource,
                    expectedLogicalBytes: Self.logicalBytes(of: resource),
                    limits: limits
                )
            } catch {
                return .unresolved(.corrupt)
            }
            let outcome = await session.contentEvidence(for: request)
            switch outcome {
            case let .complete(digest):
                digests[digest, default: []].append(resource)
            case .denied, .partial, .corrupt, .cancelled, .budgetExceeded:
                return .unresolved(outcome.code)
            }
        }
        return .complete(digests)
    }

    private func partitionResources(_ findings: [GeneralMacFinding]) -> ResourcePartition {
        var resources: [ContentResourceIdentity: [DuplicateResourceMember]] = [:]
        var unresolved: [DuplicateTriageUnresolved] = []

        for finding in findings.sorted(by: Self.findingPrecedes) {
            let member = DuplicateContentMember(
                validatedDeclaredRootID: finding.finding.declaredRoot.id,
                locator: finding.finding.locator
            )
            guard Self.hasTrustedGeneralMacScopeEvidence(finding) else {
                unresolved.append(.init(members: [member], cause: .untrustedScopeEvidence))
                continue
            }
            guard finding.completeness == .complete, finding.finding.fileKind == .regularFile else {
                unresolved.append(.init(members: [member], cause: .incompleteEvidence))
                continue
            }
            guard finding.space.isNonnegativeForDuplicateTriage,
                  Self.matchesFindingSpace(finding) else {
                unresolved.append(.init(members: [member], cause: .conflictingResourceEvidence))
                continue
            }
            guard case let .observed(volume) = finding.finding.volume,
                  case let .observed(identity) = finding.finding.resourceIdentity else {
                unresolved.append(.init(members: [member], cause: .unavailableResourceIdentity))
                continue
            }
            guard case .observed = finding.space.logicalBytes else {
                unresolved.append(.init(members: [member], cause: .unobservedLogicalSize))
                continue
            }
            let resource = ContentResourceIdentity(volume: volume, identity: identity)
            let resourceMember = DuplicateResourceMember(
                resource: resource,
                members: [member],
                space: finding.space
            )
            resources[resource, default: []].append(resourceMember)
        }

        let collapsed = resources.values.compactMap { resourceMembers -> DuplicateResourceMember? in
            guard let first = resourceMembers.first else { return nil }
            guard resourceMembers.allSatisfy({ $0.space == first.space }) else {
                unresolved.append(.init(
                    members: resourceMembers.flatMap(\.members).sorted(by: Self.memberPrecedes),
                    cause: .conflictingResourceEvidence
                ))
                return nil
            }
            return .init(
                resource: first.resource,
                members: resourceMembers.flatMap(\.members).sorted(by: Self.memberPrecedes),
                space: first.space
            )
        }
        var byLogicalSize: [Int64: [DuplicateResourceMember]] = [:]
        for resource in collapsed {
            guard case let .observed(bytes) = resource.space.logicalBytes else { continue }
            byLogicalSize[bytes, default: []].append(resource)
        }
        return .init(resourcesByLogicalSize: byLogicalSize, unresolved: unresolved)
    }

    private static func groupPrecedes(_ lhs: DuplicateGroup, _ rhs: DuplicateGroup) -> Bool {
        guard let lhsFirst = lhs.resources.first, let rhsFirst = rhs.resources.first else {
            return lhs.resources.count < rhs.resources.count
        }
        return resourcePrecedes(lhsFirst, rhsFirst)
    }

    private static func unresolvedPrecedes(_ lhs: DuplicateTriageUnresolved, _ rhs: DuplicateTriageUnresolved) -> Bool {
        let lhsKey = lhs.members.map { locatorKey($0.locator) }.joined(separator: "|")
        let rhsKey = rhs.members.map { locatorKey($0.locator) }.joined(separator: "|")
        return lhsKey < rhsKey
    }

    private static func findingPrecedes(_ lhs: GeneralMacFinding, _ rhs: GeneralMacFinding) -> Bool {
        locatorKey(lhs.finding.locator) < locatorKey(rhs.finding.locator)
    }

    private static func resourcePrecedes(_ lhs: DuplicateResourceMember, _ rhs: DuplicateResourceMember) -> Bool {
        let lhsKey = "\(lhs.resource.volume.value)/\(lhs.resource.identity.device)/\(lhs.resource.identity.node)"
        let rhsKey = "\(rhs.resource.volume.value)/\(rhs.resource.identity.device)/\(rhs.resource.identity.node)"
        return lhsKey < rhsKey
    }

    private static func memberPrecedes(_ lhs: DuplicateContentMember, _ rhs: DuplicateContentMember) -> Bool {
        locatorKey(lhs.locator) < locatorKey(rhs.locator)
    }

    private static func locatorKey(_ locator: RelativeLocator) -> String {
        "\(locator.components.joined(separator: "/"))\u{0}\(locator.rootID.value)"
    }

    private static func logicalBytes(of resource: DuplicateResourceMember) -> Int64 {
        guard case let .observed(bytes) = resource.space.logicalBytes else { return Int64.max }
        return bytes
    }

    private static func checkedRequestedBytes(for resources: [DuplicateResourceMember]) -> Int64? {
        var total: Int64 = 0
        for resource in resources {
            let (next, overflow) = total.addingReportingOverflow(logicalBytes(of: resource))
            guard !overflow else { return nil }
            total = next
        }
        return total
    }

    private static func members(in resources: [DuplicateResourceMember]) -> [DuplicateContentMember] {
        resources.flatMap(\.members).sorted(by: memberPrecedes)
    }

    private static func matchesFindingSpace(_ finding: GeneralMacFinding) -> Bool {
        finding.space.logicalBytes == finding.finding.sizes.logicalBytes
            && finding.space.allocatedBytes == finding.finding.sizes.allocatedBytes
    }

    private static func hasTrustedGeneralMacScopeEvidence(_ finding: GeneralMacFinding) -> Bool {
        let catalog = GeneralMacScopeCatalog.current
        let registration: GeneralMacScopeRegistration
        let root: DeclaredRoot
        do {
            registration = try catalog.registration(for: finding.source)
            root = try catalog.declaredRoot(for: finding.source)
        } catch {
            return false
        }
        guard finding.finding.detectorID == catalog.detectorID,
              finding.finding.detectorVersion == catalog.version,
              finding.finding.provenance == .filesystemObservation,
              finding.finding.declaredRoot == root,
              finding.finding.locator.rootID == root.id,
              finding.category == expectedCategory(for: registration, locator: finding.finding.locator),
              hasObservedSafeBoundaries(finding.finding.boundaries) else {
            return false
        }
        return true
    }

    private static func expectedCategory(
        for registration: GeneralMacScopeRegistration,
        locator: RelativeLocator
    ) -> GeneralMacCategory {
        if registration.rootKind == .userLibraryLogs,
           locator.components.first == "DiagnosticReports" {
            return .crashReport
        }
        return registration.category
    }

    private static func hasObservedSafeBoundaries(_ boundaries: BoundaryEvidence) -> Bool {
        [
            boundaries.symlink,
            boundaries.alias,
            boundaries.package,
            boundaries.mount,
            boundaries.protectedRoot,
            boundaries.homeBoundary,
            boundaries.externalVolume,
        ].allSatisfy { evidence in
            evidence == .observed(false)
        }
    }

}

private struct ResourcePartition {
    let resourcesByLogicalSize: [Int64: [DuplicateResourceMember]]
    let unresolved: [DuplicateTriageUnresolved]
}

private enum ContentCollectionResult {
    case complete([ContentDigest: [DuplicateResourceMember]])
    case unresolved(ContentEvidenceOutcomeCode)
}

private extension SpaceEvidenceVector {
    var isNonnegativeForDuplicateTriage: Bool {
        [
            logicalBytes,
            allocatedBytes,
            sharedBytes,
            conservativeReclaimableBytes,
        ].allSatisfy { evidence in
            guard case let .observed(bytes) = evidence else { return true }
            return bytes >= 0
        }
    }
}
