/// How a known owner's `~/Library/Caches` entry is explained. A class never grants
/// eligibility: only the named fixed-scope proof can, and a catalog entry always
/// yields an ineligible evaluation — so the catalog can only relabel or narrow.
public enum GeneralMacCacheOwnerClass: Equatable, Sendable {
    /// Package downloads the owning tool fetches again on demand.
    case redownloadRequired
    /// Build products, indexes, or compiled models whose loss costs the user time.
    case mayAffectWorkflow
    /// Environments or tool state the user relies on; always protected.
    case developerToolState
}

/// Known owners for `~/Library/Caches`, keyed on the first one or two locator
/// components (lowercase). A two-component key wins over its one-component prefix.
public struct GeneralMacCacheOwnerCatalog: Sendable {
    public static let current = GeneralMacCacheOwnerCatalog(
        entries: [
            ["pip"]: .redownloadRequired,
            ["homebrew"]: .redownloadRequired,
            ["uv"]: .redownloadRequired,
            ["pypoetry"]: .redownloadRequired,
            ["pypoetry", "virtualenvs"]: .developerToolState,
            ["go-build"]: .mayAffectWorkflow,
            ["org.swift.swiftpm"]: .mayAffectWorkflow,
            ["jetbrains"]: .mayAffectWorkflow,
            ["com.apple.e5rt.e5bundlecache"]: .mayAffectWorkflow,
        ]
    )

    private let entries: [[String]: GeneralMacCacheOwnerClass]

    init(entries: [[String]: GeneralMacCacheOwnerClass]) {
        self.entries = entries
    }

    /// The owner class for a locator relative to `~/Library/Caches`, or `nil` when
    /// no entry matches and the general cache rule applies unchanged.
    public func ownerClass(for components: [String]) -> GeneralMacCacheOwnerClass? {
        let prefix = components.prefix(2).map { $0.lowercased() }
        if prefix.count == 2, let owner = entries[prefix] {
            return owner
        }
        guard let first = prefix.first else { return nil }
        return entries[[first]]
    }
}
