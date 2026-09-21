public enum CanonicalPlanEncodingError: Error, Equatable, Sendable {
    case invalidLength
    case invalidNegativeValue
}

public struct CanonicalPlanEncoder: Sendable {
    public init() {}

    public func encode(_ draft: ReviewPlanDraft) throws -> [UInt8] {
        var writer = CanonicalWriter(schemaVersion: draft.versionContext.encodingVersion)
        try writer.field(1, string: draft.versionContext.appPlanVersion)
        try writer.field(2, string: draft.versionContext.policyVersion)
        try writer.field(3, string: draft.versionContext.detectorCatalogVersion)
        try writer.field(4, uint16: draft.versionContext.encodingVersion)
        try writer.field(5, string: draft.launchSession.value)
        try writer.field(6, int64: draft.createdAt.unixNanoseconds)
        try writer.field(7, int64: draft.expiresAt.unixNanoseconds)
        try writer.field(8, targets: draft.targets)
        return writer.bytes
    }
}

private struct CanonicalWriter {
    private(set) var bytes: [UInt8]

    init(schemaVersion: UInt16) {
        bytes = Array("MMCPLAN".utf8)
        bytes.append(UInt8(schemaVersion >> 8))
        bytes.append(UInt8(schemaVersion & 0xFF))
    }

    mutating func field(_ tag: UInt16, string: String) throws {
        try field(tag, payload: Array(string.utf8))
    }

    mutating func field(_ tag: UInt16, uint16: UInt16) throws {
        try field(tag, payload: [UInt8(uint16 >> 8), UInt8(uint16 & 0xFF)])
    }

    mutating func field(_ tag: UInt16, int64: Int64) throws {
        guard int64 >= 0 else { throw CanonicalPlanEncodingError.invalidNegativeValue }
        try field(tag, payload: bigEndian(UInt64(int64)))
    }

    mutating func field(_ tag: UInt16, targets: [ReviewPlanTarget]) throws {
        var payload = bigEndian(UInt32(targets.count))
        for target in targets {
            try appendTarget(target, to: &payload)
        }
        try field(tag, payload: payload)
    }

    private mutating func field(_ tag: UInt16, payload: [UInt8]) throws {
        guard UInt64(payload.count) <= UInt64.max else {
            throw CanonicalPlanEncodingError.invalidLength
        }
        bytes.append(UInt8(tag >> 8))
        bytes.append(UInt8(tag & 0xFF))
        bytes.append(contentsOf: bigEndian(UInt64(payload.count)))
        bytes.append(contentsOf: payload)
    }

    private func appendTarget(_ target: ReviewPlanTarget, to payload: inout [UInt8]) throws {
        try appendBytes(target.stableIdentity.utf8Bytes, to: &payload)
        try appendString(target.detectorID.value, to: &payload)
        try appendString(target.detectorVersion.value, to: &payload)
        try appendString(target.declaredRootID.value, to: &payload)
        payload.append(contentsOf: bigEndian(UInt32(target.locatorComponents.count)))
        for component in target.locatorComponents {
            try appendString(component, to: &payload)
        }
        payload.append(contentsOf: bigEndian(target.resourceIdentity.device))
        payload.append(contentsOf: bigEndian(target.resourceIdentity.node))
        try appendString(target.volume.value, to: &payload)
        try appendString(target.fileKind.rawValue, to: &payload)
        try appendInt64(target.logicalBytes, to: &payload)
        try appendInt64(target.allocatedBytes, to: &payload)
        try appendInt64(target.conservativeReclaimableBytes, to: &payload)
        try appendInt64(target.modificationUnixNanoseconds, to: &payload)
        payload.append(contentsOf: bigEndian(target.observationMonotonicNanoseconds))
        try appendString(target.semanticOwner.rawValue, to: &payload)
        try appendString(target.rule.identifier, to: &payload)
        try appendString(target.rule.version, to: &payload)
        try appendString(target.rationale.rawValue, to: &payload)
        try appendString(target.recoveryPath.rawValue, to: &payload)
        try appendString(target.confidence.rawValue, to: &payload)
        payload.append(UInt8(target.rankFactors.recoveryCost.rawValue))
        payload.append(UInt8(confidenceOrder(target.rankFactors.confidence)))
        payload.append(UInt8(target.rankFactors.workflowImpact.rawValue))
        try appendInt64(target.rankFactors.conservativeBytes, to: &payload)
    }

    private func appendString(_ value: String, to payload: inout [UInt8]) throws {
        try appendBytes(Array(value.utf8), to: &payload)
    }

    private func appendBytes(_ value: [UInt8], to payload: inout [UInt8]) throws {
        guard value.count <= Int(UInt32.max) else { throw CanonicalPlanEncodingError.invalidLength }
        payload.append(contentsOf: bigEndian(UInt32(value.count)))
        payload.append(contentsOf: value)
    }

    private func appendInt64(_ value: Int64, to payload: inout [UInt8]) throws {
        guard value >= 0 else { throw CanonicalPlanEncodingError.invalidNegativeValue }
        payload.append(contentsOf: bigEndian(UInt64(value)))
    }

    private func confidenceOrder(_ confidence: EvidenceConfidence) -> Int {
        switch confidence {
        case .observed: 2
        case .partial: 1
        case .unavailable: 0
        }
    }
}

private func bigEndian(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
}

private func bigEndian(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
}

private func bigEndian(_ value: UInt64) -> [UInt8] {
    [
        UInt8((value >> 56) & 0xFF),
        UInt8((value >> 48) & 0xFF),
        UInt8((value >> 40) & 0xFF),
        UInt8((value >> 32) & 0xFF),
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
}
