import CleanerCore
import Foundation

// MARK: - Model Store Adapter Support Types

enum ModelStoreVolumeIDFallback {
    static let value = try! VolumeID("unavailable")
}

enum ModelStoreDescriptorReadError: Error {
    case changed
    case denied
    case oversized
}

struct ModelStoreRootSnapshot: Sendable {
    let identity: FileIdentityEvidence
    let volume: VolumeID
}

final class ModelStoreEnumerationFaultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFault: ModelStoreDiagnosticCode?

    var fault: ModelStoreDiagnosticCode? {
        lock.lock()
        defer { lock.unlock() }
        return storedFault
    }

    func record(_ fault: ModelStoreDiagnosticCode) {
        lock.lock()
        defer { lock.unlock() }
        if storedFault == nil {
            storedFault = fault
        }
    }
}

struct ModelStoreTraversalState {
    var enumerator: FileManager.DirectoryEnumerator?
    var faultBox: ModelStoreEnumerationFaultBox?
    var deliveredCount: UInt
}
