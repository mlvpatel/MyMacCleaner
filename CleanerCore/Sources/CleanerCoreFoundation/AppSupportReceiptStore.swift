import CleanerCore
import Foundation

public struct ApplicationSupportLocator: Sendable {
    public var locate: @Sendable (FileManager) throws -> URL

    public init(locate: @escaping @Sendable (FileManager) throws -> URL) {
        self.locate = locate
    }

    public static let live = ApplicationSupportLocator { fileManager in
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}

public struct AppSupportReceiptStore: ReceiptStorePort, @unchecked Sendable {
    private let fileManager: FileManager
    private let locator: ApplicationSupportLocator
    private let publisher: DarwinReceiptPublisher

    public init(
        fileManager: FileManager,
        locator: ApplicationSupportLocator = .live,
        publisher: DarwinReceiptPublisher = .native
    ) {
        self.fileManager = fileManager
        self.locator = locator
        self.publisher = publisher
    }

    public var renameReceiptDirectory: (@Sendable (URL, URL) -> Result<Void, ReceiptPersistenceError>)?
    public var removeReceiptDirectory: (@Sendable (URL) -> Result<Void, ReceiptPersistenceError>)?

    public func persistIntent(_ intent: ReceiptIntent) async -> Result<Void, ReceiptPersistenceError> {
        switch prepareReceiptDirectory(id: intent.id) {
        case let .failure(error):
            return .failure(error)
        case let .success(directory):
            return publish(ReceiptIntentDTO(intent), directory: directory, fileName: "intent.json")
        }
    }

    public func persistTransition(
        receipt: ReceiptID,
        _ transition: ReceiptItemTransition
    ) async -> Result<Void, ReceiptPersistenceError> {
        switch prepareReceiptDirectory(id: receipt) {
        case let .failure(error):
            return .failure(error)
        case let .success(directory):
            let dto = ReceiptTransitionDTO(transition)
            return publish(dto, directory: directory, fileName: dto.fileName)
        }
    }

    public func loadAll() async -> Result<[LoadedReceiptRecord], ReceiptPersistenceError> {
        switch validatedRoot() {
        case let .failure(error):
            return .failure(error)
        case let .success(root):
            return load(from: root)
        }
    }

    public func deleteReceipt(_ id: ReceiptID) async -> Result<Void, ReceiptPersistenceError> {
        switch validatedRoot() {
        case let .failure(error):
            return .failure(error)
        case let .success(root):
            return deleteValidated(id: id, root: root)
        }
    }

    public func recoverDeletingTombstones() async -> Result<Void, ReceiptPersistenceError> {
        switch validatedRoot() {
        case let .failure(error):
            return .failure(error)
        case let .success(root):
            return recoverTombstones(in: root)
        }
    }

    public func privateMovedDestination(
        receipt: ReceiptID,
        item: ReceiptItemID
    ) async -> Result<URL, ReceiptPersistenceError> {
        switch validatedRoot() {
        case let .failure(error):
            return .failure(error)
        case let .success(root):
            return resolveMovedDestination(receipt: receipt, item: item, root: root)
        }
    }

    private func publish<Value: Encodable>(
        _ value: Value,
        directory: URL,
        fileName: String
    ) -> Result<Void, ReceiptPersistenceError> {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            return .failure(.encodeFailed)
        }
        let result = publisher.publish(data, directory, fileName)
        if case .success = result {
            let published = directory.appendingPathComponent(fileName)
            guard fileManager.isReadableFile(atPath: published.path) else {
                return .failure(.readbackFailed)
            }
        }
        return result
    }

    private func prepareReceiptDirectory(id: ReceiptID) -> Result<URL, ReceiptPersistenceError> {
        switch validatedRoot() {
        case let .failure(error):
            return .failure(error)
        case let .success(root):
            let directory = root.appendingPathComponent(id.value, isDirectory: true)
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            } catch {
                return .failure(.rootInvalid)
            }
            return .success(directory)
        }
    }

    private func validatedRoot() -> Result<URL, ReceiptPersistenceError> {
        let support: URL
        do {
            support = try locator.locate(fileManager)
        } catch {
            return .failure(.rootInvalid)
        }
        let app = support.appendingPathComponent("MyMacCleaner", isDirectory: true)
        let receipts = app.appendingPathComponent("Receipts", isDirectory: true)
        do {
            try fileManager.createDirectory(at: receipts, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: app.path)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: receipts.path)
            // Keep the trash-recovery receipts out of Time Machine / iCloud
            // backups: they are private local recovery state, not user data (D5).
            var excluded = receipts
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try excluded.setResourceValues(resourceValues)
        } catch {
            return .failure(.rootInvalid)
        }
        if publisher.isSymlink(receipts.path) || publisher.isSymlink(app.path) {
            return .failure(.rootInvalid)
        }
        if fileManager.fileExists(atPath: receipts.path),
           !publisher.ownerIsCurrentUser(receipts.path) {
            return .failure(.rootInvalid)
        }
        return .success(receipts)
    }

    private func load(from root: URL) -> Result<[LoadedReceiptRecord], ReceiptPersistenceError> {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return .failure(.readbackFailed)
        }
        var records: [LoadedReceiptRecord] = []
        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if item.lastPathComponent == "lock" { continue }
            if item.lastPathComponent.hasPrefix(".deleting-") { continue }
            records.append(loadReceipt(at: item))
        }
        return .success(records)
    }

    private func loadReceipt(at directory: URL) -> LoadedReceiptRecord {
        let intentURL = directory.appendingPathComponent("intent.json")
        guard let intentData = fileManager.contents(atPath: intentURL.path) else {
            return .unreadable
        }
        let decoder = JSONDecoder()
        let intent: ReceiptIntent
        do {
            intent = try decoder.decode(ReceiptIntentDTO.self, from: intentData).coreValue()
        } catch {
            return .unreadable
        }
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            return .unreadable
        }
        var transitions: [ReceiptItemTransition] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.lastPathComponent != "intent.json" {
            guard let data = fileManager.contents(atPath: file.path) else {
                return .unreadable
            }
            do {
                transitions.append(try decoder.decode(ReceiptTransitionDTO.self, from: data).coreValue())
            } catch {
                return .unreadable
            }
        }
        return .durable(intent: intent, transitions: transitions)
    }

    private func deleteValidated(id: ReceiptID, root: URL) -> Result<Void, ReceiptPersistenceError> {
        switch validatedChildDirectory(id: id, root: root) {
        case let .failure(error):
            return .failure(error)
        case let .success(directory):
            let tombstone = root.appendingPathComponent(".deleting-\(id.value)", isDirectory: true)
            if publisher.isSymlink(tombstone.path) {
                return .failure(.deletionRefused)
            }
            let renamed: Result<Void, ReceiptPersistenceError>
            if let renameReceiptDirectory {
                renamed = renameReceiptDirectory(directory, tombstone)
            } else {
                do {
                    try fileManager.moveItem(at: directory, to: tombstone)
                    renamed = .success(())
                } catch {
                    renamed = .failure(.renameFailed)
                }
            }
            switch renamed {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }
            switch publisher.syncDirectory(root) {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }
            return removeTombstone(tombstone)
        }
    }

    private func recoverTombstones(in root: URL) -> Result<Void, ReceiptPersistenceError> {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            return .failure(.readbackFailed)
        }
        for item in contents where item.lastPathComponent.hasPrefix(".deleting-") {
            if publisher.isSymlink(item.path) {
                return .failure(.deletionRefused)
            }
            let parent = item.standardizedFileURL.deletingLastPathComponent()
            guard parent.path == root.standardizedFileURL.path else {
                return .failure(.deletionRefused)
            }
            switch removeTombstone(item) {
            case let .failure(error):
                return .failure(error)
            case .success:
                continue
            }
        }
        return .success(())
    }

    private func removeTombstone(_ tombstone: URL) -> Result<Void, ReceiptPersistenceError> {
        if let removeReceiptDirectory {
            return removeReceiptDirectory(tombstone)
        }
        do {
            try fileManager.removeItem(at: tombstone)
            return .success(())
        } catch {
            return .failure(.writeFailed)
        }
    }

    private func validatedChildDirectory(
        id: ReceiptID,
        root: URL
    ) -> Result<URL, ReceiptPersistenceError> {
        let value = id.value
        if value == "." || value == ".." || value == "lock" || value.hasPrefix(".") {
            return .failure(.deletionRefused)
        }
        if value.contains("/") || value.contains("\\") || value.contains("\0") {
            return .failure(.deletionRefused)
        }
        let directory = root.appendingPathComponent(value, isDirectory: true)
        let standardized = directory.standardizedFileURL
        let rootStandard = root.standardizedFileURL
        guard standardized.deletingLastPathComponent().path == rootStandard.path,
              standardized.lastPathComponent == value else {
            return .failure(.deletionRefused)
        }
        if publisher.isSymlink(standardized.path) {
            return .failure(.deletionRefused)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return .failure(.unknownReceipt)
        }
        guard isDirectory.boolValue else {
            return .failure(.deletionRefused)
        }
        guard publisher.ownerIsCurrentUser(standardized.path) else {
            return .failure(.deletionRefused)
        }
        let mode: Int
        do {
            let attributes = try fileManager.attributesOfItem(atPath: standardized.path)
            mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        } catch {
            return .failure(.deletionRefused)
        }
        guard mode == 0o700 else {
            return .failure(.deletionRefused)
        }
        return .success(standardized)
    }

    private func resolveMovedDestination(
        receipt: ReceiptID,
        item: ReceiptItemID,
        root: URL
    ) -> Result<URL, ReceiptPersistenceError> {
        switch validatedChildDirectory(id: receipt, root: root) {
        case let .failure(error):
            return .failure(error)
        case let .success(directory):
            switch loadReceipt(at: directory) {
            case .unreadable, .futureSchema:
                return .failure(.readbackFailed)
            case let .durable(intent, transitions):
                let reconciled = ReceiptReconciliation().reconcile(
                    .durable(intent: intent, transitions: transitions),
                    observedAt: intent.createdAt
                )
                guard !reconciled.isQuarantined,
                      reconciled.item(item)?.state == .moved else {
                    return .failure(.unknownReceipt)
                }
                guard let destination = reconciled.item(item)?.privateDestination,
                      let url = URL(string: destination.token),
                      url.isFileURL else {
                    return .failure(.unknownReceipt)
                }
                return .success(url)
            }
        }
    }
}

private struct ReceiptIntentDTO: Codable {
    var schemaVersion: UInt16
    var receiptID: String
    var planDigest: [UInt8]
    var appPlanVersion: String
    var policyVersion: String
    var detectorCatalogVersion: String
    var encodingVersion: UInt16
    var createdAt: Int64
    var itemIDs: [String]
    var estimates: [String: EstimateDTO]

    init(_ intent: ReceiptIntent) {
        schemaVersion = intent.schemaVersion.rawValue
        receiptID = intent.id.value
        planDigest = intent.planDigest.bytes
        appPlanVersion = intent.versionReferences.appPlanVersion
        policyVersion = intent.versionReferences.policyVersion
        detectorCatalogVersion = intent.versionReferences.detectorCatalogVersion
        encodingVersion = intent.versionReferences.encodingVersion
        createdAt = intent.createdAt.unixNanoseconds
        itemIDs = intent.orderedItemIDs.map(\.value)
        estimates = Dictionary(uniqueKeysWithValues: intent.estimates.map {
            ($0.key.value, EstimateDTO($0.value))
        })
    }

    func coreValue() throws -> ReceiptIntent {
        let version = try ReceiptSchemaVersion.parse(schemaVersion)
        let ids = try itemIDs.map(ReceiptItemID.init)
        var mapped: [ReceiptItemID: ReceiptEstimateEvidence] = [:]
        for id in ids {
            guard let estimate = estimates[id.value] else { throw ReceiptValidationError.payloadStateMismatch }
            mapped[id] = try estimate.coreValue()
        }
        return try ReceiptIntent(
            id: ReceiptID(receiptID),
            schemaVersion: version,
            planDigest: PlanDigest(bytes: planDigest),
            versionReferences: ReceiptVersionReferences(
                appPlanVersion: appPlanVersion,
                policyVersion: policyVersion,
                detectorCatalogVersion: detectorCatalogVersion,
                encodingVersion: encodingVersion,
                schemaVersion: version
            ),
            createdAt: WallClockInstant(unixNanoseconds: createdAt),
            orderedItemIDs: ids,
            estimates: mapped
        )
    }
}

private struct EstimateDTO: Codable {
    var logicalBytes: Int64
    var allocatedBytes: Int64
    var conservativeReclaimableBytes: Int64

    init(_ evidence: ReceiptEstimateEvidence) {
        logicalBytes = evidence.logicalBytes
        allocatedBytes = evidence.allocatedBytes
        conservativeReclaimableBytes = evidence.conservativeReclaimableBytes
    }

    func coreValue() throws -> ReceiptEstimateEvidence {
        try ReceiptEstimateEvidence(
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            conservativeReclaimableBytes: conservativeReclaimableBytes
        )
    }
}

private struct ReceiptTransitionDTO: Codable {
    var kind: String
    var itemID: String
    var at: Int64
    var destination: String?
    var staleReason: String?
    var failure: String?

    init(_ transition: ReceiptItemTransition) {
        itemID = transition.itemID.value
        at = transition.at.unixNanoseconds
        switch transition {
        case .started:
            kind = "started"
        case let .moved(_, _, destination):
            kind = "moved"
            self.destination = destination.token
        case let .skippedStale(_, _, reason):
            kind = "skippedStale"
            staleReason = Self.encode(reason)
        case let .failed(_, _, failure):
            kind = "failed"
            self.failure = Self.encode(failure)
        case .cancelled:
            kind = "cancelled"
        }
    }

    var fileName: String {
        "\(at)-\(kind)-\(itemID).json"
    }

    func coreValue() throws -> ReceiptItemTransition {
        let id = try ReceiptItemID(itemID)
        let time = WallClockInstant(unixNanoseconds: at)
        switch kind {
        case "started":
            return .started(itemID: id, at: time)
        case "moved":
            guard let destination else { throw ReceiptValidationError.payloadStateMismatch }
            return .moved(itemID: id, at: time, destination: PrivateRecoveryDestination(token: destination))
        case "skippedStale":
            guard let staleReason, let reason = Self.decodeStale(staleReason) else {
                throw ReceiptValidationError.payloadStateMismatch
            }
            return .skippedStale(itemID: id, at: time, reason: reason)
        case "failed":
            guard let failure, let code = Self.decodeFailure(failure) else {
                throw ReceiptValidationError.payloadStateMismatch
            }
            return .failed(itemID: id, at: time, failure: code)
        case "cancelled":
            return .cancelled(itemID: id, at: time)
        default:
            throw ReceiptValidationError.payloadStateMismatch
        }
    }

    private static func encode(_ reason: TrashStaleReason) -> String {
        String(describing: reason)
    }

    private static func encode(_ failure: TrashExecutionFailure) -> String {
        String(describing: failure)
    }

    private static func decodeStale(_ raw: String) -> TrashStaleReason? {
        switch raw {
        case "identityChanged": return .identityChanged
        case "locatorChanged": return .locatorChanged
        case "rootChanged": return .rootChanged
        case "volumeChanged": return .volumeChanged
        case "fileKindChanged": return .fileKindChanged
        case "sizeChanged": return .sizeChanged
        case "modificationChanged": return .modificationChanged
        case "topologyChanged": return .topologyChanged
        case "semanticOwnerChanged": return .semanticOwnerChanged
        case "incompleteFreshEvidence": return .incompleteFreshEvidence
        case "missingFreshEvidence": return .missingFreshEvidence
        default: return nil
        }
    }

    private static func decodeFailure(_ raw: String) -> TrashExecutionFailure? {
        switch raw {
        case "nativeMoveFailed": return .nativeMoveFailed
        case "missingReturnedLocation": return .missingReturnedLocation
        default: return nil
        }
    }
}
