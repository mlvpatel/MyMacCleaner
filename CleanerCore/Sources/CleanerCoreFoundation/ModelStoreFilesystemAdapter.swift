import CleanerCore
import Foundation

public actor ModelStoreFilesystemAdapter: ModelStoreObservationPort {
    let rootURLs: [DeclaredRootID: URL]
    let fileManager: FileManager
    let environmentEvidence: [DeclaredRootID: [ModelStoreEnvironmentEvidence]]
    let maximumEntriesPerRoot: Int
    let maximumDepth: Int
    var rootSnapshots: [DeclaredRootID: ModelStoreRootSnapshot] = [:]
    var traversalStates: [DeclaredRootID: ModelStoreTraversalState] = [:]

    public init(
        rootURLs: [DeclaredRootID: URL],
        fileManager: FileManager,
        environmentEvidence: [DeclaredRootID: [ModelStoreEnvironmentEvidence]] = [:],
        maximumEntriesPerRoot: Int = ModelStoreParserLimits.maximumAllowedEntries,
        maximumDepth: Int = ModelStoreParserLimits.maximumAllowedDepth
    ) throws {
        guard !rootURLs.isEmpty else { throw ScanValidationError.emptyDeclaredRoots }
        guard maximumEntriesPerRoot > 0,
              maximumEntriesPerRoot <= ModelStoreParserLimits.maximumAllowedEntries,
              maximumDepth > 0,
              maximumDepth <= ModelStoreParserLimits.maximumAllowedDepth
        else {
            throw ModelStoreParserLimitError.excessiveLimit
        }
        self.rootURLs = rootURLs.mapValues { $0.standardizedFileURL }
        self.fileManager = fileManager
        self.environmentEvidence = environmentEvidence
        self.maximumEntriesPerRoot = maximumEntriesPerRoot
        self.maximumDepth = maximumDepth
    }

    public func rootEvidence(for root: ModelStoreRoot) async -> ModelStoreRootEvidence {
        guard let rootURL = rootURLs[root.identity.rootID],
              isExistingDirectory(rootURL),
              let volume = volumeEvidence(for: rootURL),
              let rootIdentity = observedIdentity(for: rootURL),
              let rootValues = resourceValues(for: rootURL),
              rootValues.isSymbolicLink != true,
              rootValues.isMountTrigger != true
        else {
            return fallbackRootEvidence(for: root, fault: .unavailableVolume)
        }

        rootSnapshots[root.identity.rootID] = .init(
            identity: rootIdentity,
            volume: volume
        )
        traversalStates[root.identity.rootID] = .init(enumerator: nil, faultBox: nil, deliveredCount: 0)

        return .init(
            rootID: root.identity.rootID,
            volume: volume,
            fault: nil,
            environmentEvidence: environmentEvidence[root.identity.rootID] ?? []
        )
    }

    public func nextEntry(
        after cursor: ModelStoreCursor?,
        in root: ModelStoreRoot
    ) async -> ModelStoreEntryStep {
        guard let rootURL = rootURLs[root.identity.rootID] else {
            return .fault(.unavailableVolume)
        }
        if let fault = revalidationFault(for: root, rootURL: rootURL) {
            return .fault(fault)
        }

        do {
            var state = traversalStates[root.identity.rootID] ?? .init(enumerator: nil, faultBox: nil, deliveredCount: 0)
            guard cursor?.position ?? state.deliveredCount == state.deliveredCount else {
                return .fault(.rootChanged)
            }
            guard state.deliveredCount < UInt(maximumEntriesPerRoot) else {
                return .fault(.entryLimitExceeded)
            }

            if state.enumerator == nil {
                let faultBox = ModelStoreEnumerationFaultBox()
                guard let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: Array(Self.resourceKeys),
                    options: [.skipsPackageDescendants],
                    errorHandler: { _, error in
                        faultBox.record(ModelStoreFilesystemAdapter.enumerationFault(for: error))
                        return false
                    }
                ) else {
                    return .fault(.unknownLayout)
                }
                state.enumerator = enumerator
                state.faultBox = faultBox
            }

            while let candidate = state.enumerator?.nextObject() as? URL {
                let values = try candidate.resourceValues(forKeys: Self.resourceKeys)
                guard try depth(for: candidate, rootURL: rootURL) <= maximumDepth else {
                    state.enumerator?.skipDescendants()
                    traversalStates[root.identity.rootID] = state
                    return .fault(.depthLimitExceeded)
                }
                let entry = try entryEvidence(for: candidate, values: values, rootURL: rootURL)
                if shouldDescend(values) {
                } else {
                    state.enumerator?.skipDescendants()
                }
                state.deliveredCount += 1
                traversalStates[root.identity.rootID] = state
                return .entry(entry)
            }

            traversalStates[root.identity.rootID] = state
            if let fault = state.faultBox?.fault {
                return .fault(fault)
            }
            return .complete
        } catch {
            return .fault(.unknownLayout)
        }
    }

    public func readText(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> ModelStoreTextReadResult {
        guard let rootURL = rootURLs[root.identity.rootID] else { return .failure(.missingEntry) }
        if let fault = revalidationFault(for: root, rootURL: rootURL) {
            return fault == .volumeChanged ? .failure(.volumeChanged) : .failure(.rootChanged)
        }
        guard maximumBytes > 0 else { return .failure(.missingEntry) }

        do {
            let data = try descriptorRead(
                locator: locator,
                rootID: root.identity.rootID,
                rootURL: rootURL,
                expectedIdentity: expectedIdentity,
                maximumBytes: maximumBytes
            )
            guard let text = String(data: data, encoding: .utf8) else { return .failure(.oversized) }
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch ModelStoreDescriptorReadError.oversized {
            return .failure(.oversized)
        } catch ModelStoreDescriptorReadError.changed {
            return .failure(.rootChanged)
        } catch {
            return .failure(.denied)
        }
    }

    public func inspectLink(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>
    ) async -> ModelStoreLinkInspection {
        guard let rootURL = rootURLs[root.identity.rootID] else {
            return failedLinkEvidence()
        }
        if let fault = revalidationFault(for: root, rootURL: rootURL) {
            return failedLinkEvidence(diagnostic: fault)
        }

        do {
            let destination = try descriptorReadLink(
                locator: locator,
                rootID: root.identity.rootID,
                rootURL: rootURL,
                expectedIdentity: expectedIdentity
            )
            let locator = try targetLocator(
                destination: destination,
                linkLocator: locator,
                rootURL: rootURL
            )
            let targetMetadata = descriptorTargetMetadata(
                locator: locator,
                rootID: root.identity.rootID,
                rootURL: rootURL
            )
            if let diagnostic = targetMetadata.diagnostic {
                return failedLinkEvidence(diagnostic: diagnostic)
            }
            return .init(
                target: locator,
                targetExists: targetMetadata.exists,
                targetVolume: targetMetadata.volume,
                targetKind: targetMetadata.kind
            )
        } catch ModelStoreDescriptorReadError.changed {
            return failedLinkEvidence(diagnostic: .rootChanged)
        } catch ModelStoreDescriptorReadError.denied {
            return failedLinkEvidence(diagnostic: .permissionDenied)
        } catch {
            return failedLinkEvidence()
        }
    }

    public func readOllamaManifest(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> OllamaManifestReadResult {
        let textResult = await readText(
            in: root,
            at: locator,
            expectedIdentity: expectedIdentity,
            maximumBytes: maximumBytes
        )
        guard case .success(let text) = textResult else {
            if case .failure(let fault) = textResult { return .failure(fault) }
            return .failure(.missingEntry)
        }
        guard let manifest = decodeOllamaManifest(text) else { return .failure(.missingEntry) }
        return .success(manifest)
    }

    func failedLinkEvidence(diagnostic: ModelStoreDiagnosticCode? = nil) -> ModelStoreLinkInspection {
        .init(
            target: nil,
            targetExists: false,
            targetVolume: .unavailable,
            targetKind: .unavailable,
            diagnostic: diagnostic
        )
    }

    /// Decodes only the manifest shape the pure recognizer consumes. Unknown
    /// fields are ignored, while malformed, fractional, boolean, and negative
    /// sizes are rejected before they enter the trust-core graph.
    func decodeOllamaManifest(_ text: String) -> OllamaManifestObservation? {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } catch {
            return nil
        }
        guard let object = value as? [String: Any],
              let schemaVersion = integer(object["schemaVersion"]),
              let mediaType = object["mediaType"] as? String,
              let configObject = object["config"] as? [String: Any],
              let config = layer(from: configObject),
              let rawLayers = object["layers"] as? [Any]
        else {
            return nil
        }
        var layers: [OllamaLayerObservation] = []
        for rawLayer in rawLayers {
            guard let layerObject = rawLayer as? [String: Any],
                  let layer = layer(from: layerObject)
            else {
                return nil
            }
            layers.append(layer)
        }
        return .init(
            schemaVersion: schemaVersion,
            mediaType: mediaType,
            config: config,
            layers: layers
        )
    }

    func layer(from object: [String: Any]) -> OllamaLayerObservation? {
        guard let mediaType = object["mediaType"] as? String,
              let digest = object["digest"] as? String,
              let size = integer(object["size"]),
              size >= 0
        else {
            return nil
        }
        return .init(mediaType: mediaType, digest: digest, size: size)
    }

    func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              String(cString: number.objCType) != "c",
              number.doubleValue.isFinite,
              number.doubleValue >= Double(Int.min),
              number.doubleValue <= Double(Int.max)
        else {
            return nil
        }
        let integer = number.intValue
        return Double(integer) == number.doubleValue ? integer : nil
    }

    static let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey,
        .isAliasFileKey,
        .isDirectoryKey,
        .isMountTriggerKey,
        .isPackageKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
    ]
}
