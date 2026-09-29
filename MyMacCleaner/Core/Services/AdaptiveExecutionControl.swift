import CleanerCore
import Foundation

// MARK: - Approval Binding

/// Converts the plan digest the user reviewed (as projected hex) back into a `PlanDigest`
/// so the approval attestation carries what was displayed, not whatever plan is current.
enum AdaptiveApprovalBinding {
    private static let digestByteCount = 32

    /// Decodes lowercase hex as produced by the Adaptive Experience projection.
    static func digest(fromHex hex: String) -> PlanDigest? {
        let characters = Array(hex.utf8)
        guard characters.count == digestByteCount * 2,
              hex.allSatisfy("0123456789abcdef".contains) else { return nil }
        let bytes = stride(from: 0, to: characters.count, by: 2).compactMap {
            UInt8(String(decoding: characters[$0..<$0 + 2], as: UTF8.self), radix: 16)
        }
        return try? PlanDigest(bytes: bytes)
    }
}

// MARK: - Run Cancellation

/// Thread-safe, one-way cancellation flag read synchronously between Trash moves.
final class TrashRunCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

// MARK: - Session Failures

/// Why the Adaptive session could not show evidence or finish a run. Every case is shown to the user.
enum AdaptiveSessionFailure: Error, Equatable, Sendable {
    /// Launch session or plan version context could not be created, so no plan can be approved.
    case sessionUnavailable
    /// Evidence collection failed.
    case scanFailed
    /// Evidence was collected but could not be projected for display.
    case presentationFailed
    /// The approval no longer matches the displayed plan (refreshed, expired or changed). Nothing moved.
    case planChanged
    /// Receipt history could not be opened, so no run was started.
    case receiptHistoryUnavailable

    var messageKey: String {
        switch self {
        case .sessionUnavailable: return "adaptive.failure.sessionUnavailable"
        case .scanFailed: return "adaptive.failure.scanFailed"
        case .presentationFailed: return "adaptive.failure.presentationFailed"
        case .planChanged: return "adaptive.failure.planChanged"
        case .receiptHistoryUnavailable: return "adaptive.failure.receiptHistoryUnavailable"
        }
    }
}

// MARK: - Plan Versions

/// Versions stamped into every review plan and receipt. `appPlan` is the plan format version,
/// not the marketing version; bump it when plan encoding or approval semantics change.
enum AdaptivePlanVersions {
    static let appPlan = "5.0.0"
    static let policy = "policy-1"
    static let encoding: UInt16 = 1
}
