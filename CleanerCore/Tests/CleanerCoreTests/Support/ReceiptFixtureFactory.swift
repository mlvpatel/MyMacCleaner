@testable import CleanerCore

enum ReceiptFixtureFactory {
    static let t0 = WallClockInstant(unixNanoseconds: 1_000)
    static let t1 = WallClockInstant(unixNanoseconds: 1_001)
    static let t2 = WallClockInstant(unixNanoseconds: 1_002)
    static let hostileToken = "file:///Users/secret/.Trash/model.bin"

    static func intent(id: String = "receipt-hostile", item: String = "item-a") throws -> ReceiptIntent {
        let itemID = try ReceiptItemID(item)
        return try ReceiptIntent(
            id: ReceiptID(id),
            schemaVersion: .v1,
            planDigest: PlanDigest(bytes: Array(repeating: 9, count: 32)),
            versionReferences: ReceiptVersionReferences(
                appPlanVersion: "5.0.0",
                policyVersion: "policy-1",
                detectorCatalogVersion: "catalog-1",
                encodingVersion: 1,
                schemaVersion: .v1
            ),
            createdAt: t0,
            orderedItemIDs: [itemID],
            estimates: [
                itemID: try ReceiptEstimateEvidence(
                    logicalBytes: 4_096,
                    allocatedBytes: 4_096,
                    conservativeReclaimableBytes: 4_096
                )
            ]
        )
    }

    static func started(item: String = "item-a") throws -> ReceiptItemTransition {
        .started(itemID: try ReceiptItemID(item), at: t1)
    }

    static func moved(item: String = "item-a") throws -> ReceiptItemTransition {
        .moved(
            itemID: try ReceiptItemID(item),
            at: t2,
            destination: PrivateRecoveryDestination(token: hostileToken)
        )
    }
}
