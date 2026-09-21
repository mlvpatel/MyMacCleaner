public struct ModelStoreAccounting: Equatable, Sendable {
    public let summary: ModelStoreAccountingSummary

    public init(graph: ModelStoreGraph) {
        summary = Self.summarize(graph)
    }

    private static func summarize(_ graph: ModelStoreGraph) -> ModelStoreAccountingSummary {
        guard let blobsByKey = blobMap(graph.blobs) else {
            return unavailableSummary
        }

        let logicalReferencedBytes = observedSum(graph.snapshotBlobEdges.map { edge in
            blobsByKey[.init(repositoryID: edge.repositoryID, blobID: edge.blobID)]?.logicalBytes ?? .unavailable
        })

        let uniquePhysicalBlobs = uniqueBlobs(graph.blobs)
        let uniquePhysicalBytes: EvidenceValue<Int>
        if let uniquePhysicalBlobs {
            uniquePhysicalBytes = observedSum(uniquePhysicalBlobs.map(\.logicalBytes))
        } else {
            uniquePhysicalBytes = .unavailable
        }

        let sharedBytes: EvidenceValue<Int>
        if let uniquePhysicalBlobs,
           let sharedIdentities = sharedPhysicalIdentities(edges: graph.snapshotBlobEdges, blobsByKey: blobsByKey) {
            sharedBytes = observedSum(
                uniquePhysicalBlobs
                    .filter { blob in
                        physicalIdentity(for: blob).map { sharedIdentities.contains($0) } ?? false
                    }
                    .map(\.logicalBytes)
            )
        } else {
            sharedBytes = .unavailable
        }

        let incompleteBytes: EvidenceValue<Int>
        if let incompleteBlobs = uniqueBlobs(graph.incompleteBlobs) {
            incompleteBytes = observedSum(incompleteBlobs.map(\.logicalBytes))
        } else {
            incompleteBytes = .unavailable
        }

        return .init(
            logicalReferencedBytes: logicalReferencedBytes,
            uniquePhysicalBytes: uniquePhysicalBytes,
            sharedBytesIncludedInUniquePhysical: minObserved(sharedBytes, uniquePhysicalBytes),
            locallyObservedIncompleteBytes: incompleteBytes,
            reclaimability: .protectedNotEligible
        )
    }

    private static var unavailableSummary: ModelStoreAccountingSummary {
        .init(
            logicalReferencedBytes: .unavailable,
            uniquePhysicalBytes: .unavailable,
            sharedBytesIncludedInUniquePhysical: .unavailable,
            locallyObservedIncompleteBytes: .unavailable,
            reclaimability: .protectedNotEligible
        )
    }

    private static func blobMap(_ blobs: [ModelStoreBlob]) -> [BlobKey: ModelStoreBlob]? {
        var result: [BlobKey: ModelStoreBlob] = [:]
        for blob in blobs {
            let key = BlobKey(repositoryID: blob.identity.repositoryID, blobID: blob.identity.blobID)
            if let existing = result[key], existing != blob { return nil }
            result[key] = blob
        }
        return result
    }

    private static func sharedPhysicalIdentities(
        edges: [ModelStoreSnapshotBlobEdge],
        blobsByKey: [BlobKey: ModelStoreBlob]
    ) -> Set<String>? {
        var counts: [String: Int] = [:]
        for edge in edges {
            guard let blob = blobsByKey[.init(repositoryID: edge.repositoryID, blobID: edge.blobID)],
                  let identity = physicalIdentity(for: blob)
            else { return nil }
            let next = (counts[identity] ?? 0).addingReportingOverflow(1)
            guard !next.overflow else { return nil }
            counts[identity] = next.partialValue
        }
        return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
    }

    private static func uniqueBlobs(_ blobs: [ModelStoreBlob]) -> [ModelStoreBlob]? {
        var observedKeys: [String: ModelStoreBlob] = [:]
        var result: [ModelStoreBlob] = []

        for blob in blobs {
            guard let key = physicalIdentity(for: blob) else { return nil }
            if let existing = observedKeys[key] {
                guard existing.logicalBytes == blob.logicalBytes else { return nil }
                continue
            }
            observedKeys[key] = blob
            result.append(blob)
        }

        return result
    }

    private static func physicalIdentity(for blob: ModelStoreBlob) -> String? {
        guard case .observed(let identity) = blob.identity.fileIdentity else { return nil }
        return "identity:\(identity.device):\(identity.node)"
    }

    private static func observedSum(_ values: [EvidenceValue<Int>]) -> EvidenceValue<Int> {
        var total = 0
        for value in values {
            switch value {
            case .observed(let bytes) where bytes >= 0:
                guard let sum = checkedAdd(total, bytes) else {
                    return .unavailable
                }
                total = sum
            case .observed, .unknown, .unavailable:
                return .unavailable
            }
        }
        return .observed(total)
    }

    private static func minObserved(_ lhs: EvidenceValue<Int>, _ rhs: EvidenceValue<Int>) -> EvidenceValue<Int> {
        switch (lhs, rhs) {
        case (.observed(let left), .observed(let right)):
            return .observed(min(left, right))
        case (.unknown, _), (_, .unknown):
            return .unknown
        case (.unavailable, _), (_, .unavailable):
            return .unavailable
        }
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) -> Int? {
        let (sum, overflow) = lhs.addingReportingOverflow(max(0, rhs))
        return overflow ? nil : sum
    }
}

private struct BlobKey: Hashable {
    let repositoryID: String
    let blobID: String
}

public struct ModelStoreAccountingSummary: Equatable, Sendable {
    public let logicalReferencedBytes: EvidenceValue<Int>
    public let uniquePhysicalBytes: EvidenceValue<Int>
    public let sharedBytesIncludedInUniquePhysical: EvidenceValue<Int>
    public let locallyObservedIncompleteBytes: EvidenceValue<Int>
    public let reclaimability: ModelStoreReclaimability
}

public enum ModelStoreReclaimability: Equatable, Sendable {
    case protectedNotEligible
}
