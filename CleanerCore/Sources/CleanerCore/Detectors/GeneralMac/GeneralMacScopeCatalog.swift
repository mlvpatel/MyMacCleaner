public enum GeneralMacRootKind: Hashable, Sendable {
    case userLibraryCaches
    case userLibraryLogs
    case userTemporary
    case userDownloads
    case userDesktop
    case userDocuments
}

public struct GeneralMacScopeID: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) { self.value = value }
}

public struct GeneralMacScanLimits: Equatable, Sendable {
    public static let current = GeneralMacScanLimits(
        maximumDepth: 8,
        maximumEntriesPerRoot: 25_000,
        maximumFindingsPerRoot: 10_000,
        maximumObservedLogicalBytesPerRoot: 1_099_511_627_776,
        maximumFindingsPerBatch: 128,
        maximumRootsPerRequest: 6
    )

    public let maximumDepth: Int
    public let maximumEntriesPerRoot: Int
    public let maximumFindingsPerRoot: Int
    public let maximumObservedLogicalBytesPerRoot: Int64
    public let maximumFindingsPerBatch: Int
    public let maximumRootsPerRequest: Int
}

public struct GeneralMacScopeRegistration: Equatable, Sendable {
    public let id: GeneralMacScopeID
    public let rootKind: GeneralMacRootKind
    public let category: GeneralMacCategory

    init(id: GeneralMacScopeID, rootKind: GeneralMacRootKind, category: GeneralMacCategory) {
        self.id = id
        self.rootKind = rootKind
        self.category = category
    }
}

public enum GeneralMacScopeCatalogError: Error, Equatable, Sendable {
    case unknownScope
    case tooManyRoots
    case duplicateScope
    case invalidLimits
}

public struct GeneralMacScopeCatalog: Sendable {
    public static let current = try! GeneralMacScopeCatalog(
        version: try! DetectorVersion("1.0.0"),
        registrations: [
            .init(id: .init("user-library-caches"), rootKind: .userLibraryCaches, category: .cache),
            .init(id: .init("user-library-logs"), rootKind: .userLibraryLogs, category: .log),
            .init(id: .init("user-temporary"), rootKind: .userTemporary, category: .temporary),
            .init(id: .init("user-downloads"), rootKind: .userDownloads, category: .largeFile),
            .init(id: .init("user-desktop"), rootKind: .userDesktop, category: .largeFile),
            .init(id: .init("user-documents"), rootKind: .userDocuments, category: .largeFile),
        ]
    )

    public let detectorID: DetectorID
    public let version: DetectorVersion
    public let registrations: [GeneralMacScopeRegistration]
    public let limits: GeneralMacScanLimits

    init(
        version: DetectorVersion,
        registrations: [GeneralMacScopeRegistration],
        limits: GeneralMacScanLimits = .current
    ) throws {
        guard registrations.count <= limits.maximumRootsPerRequest,
              Set(registrations.map(\.id)).count == registrations.count,
              limits.maximumDepth > 0,
              limits.maximumEntriesPerRoot > 0,
              limits.maximumFindingsPerRoot > 0,
              limits.maximumObservedLogicalBytesPerRoot > 0,
              limits.maximumFindingsPerBatch > 0,
              limits.maximumRootsPerRequest > 0 else {
            throw GeneralMacScopeCatalogError.invalidLimits
        }
        detectorID = try! DetectorID("general.mac.storage")
        self.version = version
        self.registrations = registrations
        self.limits = limits
    }

    public func registration(for kind: GeneralMacRootKind) throws -> GeneralMacScopeRegistration {
        guard let registration = registrations.first(where: { $0.rootKind == kind }) else {
            throw GeneralMacScopeCatalogError.unknownScope
        }
        return registration
    }

    public func declaredRoot(for kind: GeneralMacRootKind) throws -> DeclaredRoot {
        .init(id: try DeclaredRootID(registration(for: kind).id.value))
    }

    public func rootKind(for rootID: DeclaredRootID) throws -> GeneralMacRootKind {
        guard let registration = registrations.first(where: { $0.id.value == rootID.value }) else {
            throw GeneralMacScopeCatalogError.unknownScope
        }
        return registration.rootKind
    }

    public func scanRequest(for roots: [GeneralMacRootKind]) throws -> ScanRequest {
        guard !roots.isEmpty, roots.count <= limits.maximumRootsPerRequest else {
            throw GeneralMacScopeCatalogError.tooManyRoots
        }
        guard Set(roots).count == roots.count else {
            throw GeneralMacScopeCatalogError.duplicateScope
        }
        let declaredRoots = try roots.map(declaredRoot)
        let budget = try ScanBudget(
            maximumFindings: limits.maximumFindingsPerBatch,
            maximumObservations: limits.maximumFindingsPerBatch,
            maximumDepth: limits.maximumDepth,
            maximumEntries: limits.maximumEntriesPerRoot,
            maximumBatches: 1_200,
            maximumObservedBytes: limits.maximumObservedLogicalBytesPerRoot,
            maximumFindingsPerRoot: limits.maximumFindingsPerRoot,
            maximumRootsPerRequest: limits.maximumRootsPerRequest
        )
        return try ScanRequest(declaredRoots: declaredRoots, budget: budget)
    }
}
