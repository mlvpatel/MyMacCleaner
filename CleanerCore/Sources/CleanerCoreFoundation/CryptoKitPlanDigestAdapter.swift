import CleanerCore
import CryptoKit
import Foundation

public struct CryptoKitPlanDigestAdapter: PlanDigesting {
    public init() {}

    public func digest(canonicalBytes: [UInt8]) throws -> PlanDigest {
        try PlanDigest(bytes: Array(SHA256.hash(data: Data(canonicalBytes))))
    }
}
