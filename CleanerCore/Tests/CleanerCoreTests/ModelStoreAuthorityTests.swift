import Foundation
import Testing

@testable import CleanerCore

@Suite("Model Store Authority")
struct ModelStoreAuthorityTests {
    @Test
    func registryExposesOnlyFixedVersionedModelStoreDetectors() throws {
        let selections = [
            ModelStoreDetectorRegistration.huggingFaceSelection,
            ModelStoreDetectorRegistration.ollamaSelection,
            ModelStoreDetectorRegistration.selectedRootSelection,
        ]
        let registry = try DetectorRegistry(registrations: ModelStoreDetectorRegistration.registrations)

        #expect(registry.availableSelections.count == selections.count)
        for selection in selections {
            #expect(registry.availableSelections.contains(selection))
        }
        #expect(throws: DetectorRegistryError.unknownDetector) {
            _ = try registry.resolve(.init(id: DetectorID("modelstore.unknown"), version: DetectorVersion("1.0.0")))
        }
        #expect(throws: DetectorRegistryError.unsupportedVersion) {
            _ = try registry.resolve(.init(id: ModelStoreDetector.ollamaV1.id, version: DetectorVersion("2.0.0")))
        }
    }

    @Test(arguments: projectionCases)
    fileprivate func projectionIsAlwaysProtectedAndNonSelected(_ testCase: ModelStoreProjectionCase) throws {
        let rootID = try DeclaredRootID("projection-root")
        let graph = ModelStoreGraph(
            detector: .huggingFaceV1,
            roots: [
                .init(
                    identity: .init(rootID: rootID),
                    authority: .documentedDefault(.huggingFaceCache),
                    layout: .huggingFaceCacheV1
                )
            ],
            repositories: [],
            refs: [],
            snapshots: [],
            blobs: [],
            incompleteBlobs: [],
            snapshotBlobEdges: [],
            diagnostics: testCase.diagnostics,
            environmentEvidence: [],
            protection: .inspectOnly(reason: testCase.reason)
        )

        let projection = ModelStoreProjection(
            result: .init(outcome: testCase.outcome, graph: graph)
        )

        #expect(projection.state == ProjectedScanState(testCase.outcome))
        #expect(projection.entries.allSatisfy { $0.isSelected == false })
        #expect(projection.entries.allSatisfy {
            $0.reclaimability == ModelStoreReclaimability.protectedNotEligible
        })
        #expect(projection.entries.allSatisfy { $0.operation == nil })
        #expect(projection.protectionReason == testCase.reason)
    }

    @Test
    func projectionPreservesDetectorVersionAndGraphRelationships() throws {
        let rootID = try DeclaredRootID("projection-graph-root")
        let graph = ModelStoreGraph(
            detector: .huggingFaceV1,
            roots: [
                .init(
                    identity: .init(rootID: rootID),
                    authority: .documentedDefault(.huggingFaceCache),
                    layout: .huggingFaceCacheV1
                )
            ],
            repositories: [.init(identity: .init(repositoryID: "models--owner--repo"))],
            refs: [.init(repositoryID: "models--owner--repo", name: "main", targetSnapshot: "abc123")],
            snapshots: [.init(repositoryID: "models--owner--repo", snapshotID: "abc123")],
            blobs: [
                .init(
                    identity: .init(repositoryID: "models--owner--repo", blobID: "sha256", fileIdentity: .unavailable),
                    logicalBytes: 1
                )
            ],
            incompleteBlobs: [],
            snapshotBlobEdges: [
                .init(
                    repositoryID: "models--owner--repo",
                    snapshotID: "abc123",
                    snapshotFileName: "model.bin",
                    blobID: "sha256"
                )
            ],
            diagnostics: [],
            environmentEvidence: [],
            protection: .inspectOnly(reason: .inventoryOnly)
        )

        let projection = ModelStoreProjection(result: .init(outcome: .complete, graph: graph))

        #expect(projection.detectorID == ModelStoreDetector.huggingFaceV1.id)
        #expect(projection.detectorVersion == ModelStoreDetector.huggingFaceV1.version)
        #expect(projection.repositories.map { $0.identity.repositoryID } == ["models--owner--repo"])
        #expect(projection.refs.map { $0.targetSnapshot } == ["abc123"])
        #expect(projection.snapshots.map { $0.snapshotID } == ["abc123"])
        #expect(projection.blobs.map { $0.identity.blobID } == ["sha256"])
        #expect(projection.snapshotBlobEdges.map { $0.blobID } == ["sha256"])
    }

    @Test
    func forgedDefaultRootIdentityIsRejectedBeforeAnyPortCall() async throws {
        let forgedRootID = try DeclaredRootID("forged-default-root")
        let port = ScriptedModelStorePort(
            rootID: forgedRootID,
            rootVolume: try VolumeID("volume:forged"),
            environmentEvidence: [],
            entries: [.directory(["models--owner--repo"])]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )
        let forgedRoot = ModelStoreRoot(
            identity: .init(rootID: forgedRootID),
            authority: .documentedDefault(.huggingFaceCache),
            layout: .huggingFaceCacheV1
        )

        let result = await parser.parse(root: forgedRoot)

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.diagnostics.map { $0.code } == [.unauthorizedRoot])
        #expect(port.calls.isEmpty)
    }

    @Test
    func unvalidatedExplicitRootIsRejectedBeforeAnyPortCall() async throws {
        let rootID = try DeclaredRootID("unvalidated-explicit-root")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:unvalidated"),
            environmentEvidence: [],
            entries: [.directory(["models--owner--repo"])]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(
            root: .explicitlySelected(rootID: rootID, selection: .unvalidated)
        )

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.diagnostics.map { $0.code } == [.unauthorizedRoot])
        #expect(port.calls.isEmpty)
    }

    @Test
    func modelInventorySourcesDoNotExposeOperationVocabulary() throws {
        let forbidden = [
            "CleanableItem",
            "PolicyPort",
            "ExecutionPort",
            "ReceiptPort",
            "Process",
            "URLSession",
            "shell",
            "delete",
            "removeItem",
        ]
        let sources = try modelInventorySourceText([
            "ModelStoreGraph.swift",
            "HuggingFaceCacheParser.swift",
            "OllamaStoreParser.swift",
            "SelectedRootInventory.swift",
            "ModelAssociation.swift",
            "ModelStoreAccounting.swift",
            "ModelStoreProjection.swift",
        ])

        for token in forbidden {
            #expect(!sources.contains(token))
        }
    }

    @Test(arguments: [
        ModelAssociationEvidence.unknown,
        ModelAssociationEvidence(strength: .inferred, kind: .namedLocalFormatEvidence)!,
        ModelAssociationEvidence(strength: .proven, kind: .explicitFormatField)!,
    ])
    func everyVendorProjectionRemainsNonOperableWithAnyAssociation(
        _ association: ModelAssociationEvidence
    ) throws {
        let rootID = try DeclaredRootID("authority-\(association.strength)")
        let roots: [(ModelStoreDetector, ModelStoreRoot)] = [
            (.huggingFaceV1, .defaultHuggingFaceCache()),
            (.ollamaV1, .defaultOllamaModels()),
            (.selectedRootV1, .explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)),
        ]
        for (detector, root) in roots {
            let result = ModelStoreParseResult(
                outcome: .complete,
                graph: .init(
                    detector: detector,
                    roots: [root],
                    repositories: [], refs: [], snapshots: [], blobs: [], incompleteBlobs: [], snapshotBlobEdges: [],
                    diagnostics: [], environmentEvidence: [], association: association,
                    protection: .inspectOnly(reason: .inventoryOnly)
                )
            )
            let projection = ModelStoreProjection(result: result)
            #expect(projection.association == association)
            #expect(projection.entries.allSatisfy { !$0.isSelected && $0.operation == nil })
            #expect(projection.entries.allSatisfy { $0.reclaimability == .protectedNotEligible })
        }
    }

    @Test
    func selectedRootTokenConstructionIsPackageScoped() throws {
        let forbidden = [
            "public static let validated",
            "public static let unvalidated",
            "public init(isValidated:",
        ]
        let source = try modelInventorySourceText(["ModelStoreGraph.swift"])

        for token in forbidden {
            #expect(!source.contains(token))
        }
        #expect(source.contains("package static let validated"))
        #expect(source.contains("private init(isValidated:"))
    }
}

private func modelInventorySourceText(_ fileNames: [String]) throws -> String {
    let currentFile = URL(fileURLWithPath: #filePath)
    let packageRoot = currentFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try fileNames.map { fileName in
        let subdirectory = fileName == "ModelStoreProjection.swift" ? "Bridge" : "ModelInventory"
        let url = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("CleanerCore")
            .appendingPathComponent(subdirectory)
            .appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8)
    }.joined(separator: "\n")
}

private struct ModelStoreProjectionCase: Sendable {
    let outcome: ScanOutcome
    let diagnostics: [ModelStoreDiagnostic]
    let reason: ModelStoreProtectionReason
}

private let projectionCases: [ModelStoreProjectionCase] = [
    .init(outcome: .complete, diagnostics: [], reason: .inventoryOnly),
    .init(
        outcome: .corruptMetadata,
        diagnostics: [.init(code: .corruptRef)],
        reason: .corruptRef
    ),
    .init(
        outcome: .unsupportedLayout,
        diagnostics: [.init(code: .escapingLink)],
        reason: .boundaryViolation
    ),
    .init(
        outcome: .cancelled,
        diagnostics: [.init(code: .cancelled)],
        reason: .cancelled
    ),
]

final class ScriptedModelStorePort: ModelStoreObservationPort, @unchecked Sendable {
    private let rootID: DeclaredRootID
    private let rootVolume: VolumeID
    private let environmentEvidence: [ModelStoreEnvironmentEvidence]
    private let rootFault: ModelStoreRootFault?
    private let entries: [ModelStoreEntryEvidence]
    private let ollamaManifests: [[String]: OllamaManifestObservation]
    private let normalizeEntryMetadata: Bool

    private(set) var calls: [ModelStorePortCall] = []

    init(
        rootID: DeclaredRootID,
        rootVolume: VolumeID,
        environmentEvidence: [ModelStoreEnvironmentEvidence],
        rootFault: ModelStoreRootFault? = nil,
        entries: [ModelStoreEntryEvidence],
        ollamaManifests: [[String]: OllamaManifestObservation] = [:],
        normalizeEntryMetadata: Bool = true
    ) {
        self.rootID = rootID
        self.rootVolume = rootVolume
        self.environmentEvidence = environmentEvidence
        self.rootFault = rootFault
        self.entries = entries
        self.ollamaManifests = ollamaManifests
        self.normalizeEntryMetadata = normalizeEntryMetadata
    }

    func rootEvidence(for root: ModelStoreRoot) async -> ModelStoreRootEvidence {
        calls.append(.rootEvidence(root.identity.rootID))
        return .init(
            rootID: rootID,
            volume: rootVolume,
            fault: rootFault,
            environmentEvidence: environmentEvidence
        )
    }

    func nextEntry(after cursor: ModelStoreCursor?, in root: ModelStoreRoot) async -> ModelStoreEntryStep {
        calls.append(.nextEntry(cursor?.position))
        let index = Int(cursor?.position ?? 0)
        guard index < entries.count else { return .complete }
        return .entry(normalize(entries[index]))
    }

    func readText(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> ModelStoreTextReadResult {
        calls.append(.readText(root.identity.rootID, locator.components, maximumBytes: maximumBytes))
        guard let entry = entries.first(where: { $0.locator.components == locator.components }) else {
            return .failure(.missingEntry)
        }
        guard normalize(entry).fileIdentity == expectedIdentity else { return .failure(.rootChanged) }
        guard let text = entry.text else { return .failure(.missingEntry) }
        guard case .observed(let bytes) = entry.size.logicalBytes,
              bytes <= maximumBytes
        else {
            return .failure(.oversized)
        }
        return .success(text)
    }

    func inspectLink(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>
    ) async -> ModelStoreLinkInspection {
        calls.append(.inspectLink(root.identity.rootID, locator.components))
        guard let entry = entries.first(where: { $0.locator.components == locator.components }),
              let link = entry.link
        else {
            return .init(target: nil, targetExists: false, targetVolume: .unavailable, targetKind: .unavailable)
        }
        guard normalize(entry).fileIdentity == expectedIdentity else {
            return .init(
                target: nil,
                targetExists: false,
                targetVolume: .unavailable,
                targetKind: .unavailable,
                diagnostic: .rootChanged
            )
        }
        return link
    }

    func readOllamaManifest(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> OllamaManifestReadResult {
        calls.append(.readOllamaManifest(root.identity.rootID, locator.components, maximumBytes: maximumBytes))
        guard let entry = entries.first(where: { $0.locator.components == locator.components }) else {
            return .failure(.missingEntry)
        }
        guard normalize(entry).fileIdentity == expectedIdentity else { return .failure(.rootChanged) }
        guard case .observed(let bytes) = entry.size.logicalBytes, bytes <= maximumBytes else {
            return .failure(.oversized)
        }
        guard let manifest = ollamaManifests[locator.components] else { return .failure(.missingEntry) }
        return .success(manifest)
    }

    private func normalize(_ entry: ModelStoreEntryEvidence) -> ModelStoreEntryEvidence {
        guard normalizeEntryMetadata else { return entry }
        let normalizedIdentity: EvidenceValue<FileIdentityEvidence>
        switch entry.fileIdentity {
        case .observed:
            normalizedIdentity = entry.fileIdentity
        case .unknown, .unavailable:
            let seed = UInt64(abs(entry.locator.components.joined(separator: "/").hashValue))
            normalizedIdentity = .observed(.init(device: 10, node: seed == 0 ? 1 : seed))
        }
        let normalizedVolume: EvidenceValue<VolumeID>
        switch entry.volume {
        case .observed:
            normalizedVolume = entry.volume
        case .unknown, .unavailable:
            normalizedVolume = .observed(rootVolume)
        }
        return .init(
            locator: entry.locator,
            kind: entry.kind,
            size: entry.size,
            fileIdentity: normalizedIdentity,
            volume: normalizedVolume,
            text: entry.text,
            link: entry.link,
            topology: entry.topology
        )
    }
}

enum ModelStorePortCall: Equatable, Sendable {
    case rootEvidence(DeclaredRootID)
    case nextEntry(UInt?)
    case readText(DeclaredRootID, [String], maximumBytes: Int)
    case inspectLink(DeclaredRootID, [String])
    case readOllamaManifest(DeclaredRootID, [String], maximumBytes: Int)
}

struct NeverCancelledModelStoreCancellation: ModelStoreCancellation {
    func isCancellationRequested() async -> Bool { false }
}

final class ScriptedModelStoreCancellation: ModelStoreCancellation, @unchecked Sendable {
    private var responses: [Bool]

    init(responses: [Bool]) {
        self.responses = responses
    }

    func isCancellationRequested() async -> Bool {
        guard !responses.isEmpty else { return false }
        return responses.removeFirst()
    }
}

extension ModelStoreEntryEvidence {
    static func directory(_ components: [String]) -> ModelStoreEntryEvidence {
        .init(
            locator: try! .init(components),
            kind: .directory,
            size: .init(logicalBytes: 0),
            fileIdentity: .unavailable,
            volume: .unavailable,
            text: nil,
            link: nil
        )
    }

    static func file(
        _ components: [String],
        bytes: Int,
        identity: FileIdentityEvidence? = nil,
        text: String? = nil
    ) -> ModelStoreEntryEvidence {
        .init(
            locator: try! .init(components),
            kind: .regularFile,
            size: .init(logicalBytes: bytes),
            fileIdentity: identity.map(EvidenceValue.observed) ?? .unavailable,
            volume: .unavailable,
            text: text,
            link: nil
        )
    }

    static func symlink(
        _ components: [String],
        target: [String],
        targetExists: Bool = true,
        targetVolume: VolumeID? = nil,
        targetKind: ModelStoreEntryKind? = .regularFile
    ) -> ModelStoreEntryEvidence {
        .init(
            locator: try! .init(components),
            kind: .symbolicLink,
            size: .init(logicalBytes: 0),
            fileIdentity: .unavailable,
            volume: .unavailable,
            text: nil,
            link: .init(
                target: try! .init(target),
                targetExists: targetExists,
                targetVolume: targetVolume.map(EvidenceValue.observed) ?? .unavailable,
                targetKind: targetKind.map(EvidenceValue.observed) ?? .unavailable
            )
        )
    }
}
