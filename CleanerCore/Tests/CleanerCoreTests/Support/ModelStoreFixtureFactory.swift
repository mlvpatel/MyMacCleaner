import Testing

@testable import CleanerCore

enum ModelStoreFixtureFactory {
    struct HuggingFaceFixture: Sendable {
        let root: ModelStoreRoot
        let port: ScriptedModelStorePort
    }

    static func changedHuggingFaceRootIdentity() throws -> HuggingFaceFixture {
        let observedRootID = try DeclaredRootID("synthetic-huggingface-replaced-root")
        let volume = try VolumeID("volume:synthetic-huggingface")
        return .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: observedRootID,
                rootVolume: volume,
                environmentEvidence: [],
                entries: [.directory(["models--synthetic--repo"])]
            )
        )
    }

    static func unsupportedOllamaManifest() throws -> OllamaFixture {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:synthetic-ollama")
        let manifestLocator = ["manifests", "registry", "synthetic", "demo", "latest"]
        return .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: rootID,
                rootVolume: volume,
                environmentEvidence: [],
                entries: [.file(manifestLocator, bytes: 128, identity: .init(device: 51, node: 1))],
                ollamaManifests: [
                    manifestLocator: .init(
                        schemaVersion: 1,
                        mediaType: "application/vnd.docker.distribution.manifest.v2+json",
                        config: .init(mediaType: "application/vnd.ollama.image.config", digest: validDigest("a"), size: 1),
                        layers: []
                    ),
                ]
            )
        )
    }

    static func changedOllamaStore() throws -> OllamaFixture {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        return .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-ollama-changed"),
                environmentEvidence: [],
                rootFault: .volumeChanged,
                entries: []
            )
        )
    }

    static func partialHuggingFaceStore() throws -> HuggingFaceFixture {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        return .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-huggingface-partial"),
                environmentEvidence: [],
                entries: [
                    .directory(["models--synthetic--repo"]),
                    .directory(["unexpected-layout"]),
                ]
            )
        )
    }

    static func sharedHuggingFaceStore() throws -> HuggingFaceFixture {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let volume = try VolumeID("volume:synthetic-huggingface-shared")
        let repository = "models--synthetic--shared"
        let blob = [repository, "blobs", "sha256"]
        return .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: rootID,
                rootVolume: volume,
                environmentEvidence: [],
                entries: [
                    .directory([repository]),
                    .directory([repository, "refs"]),
                    .file([repository, "refs", "main"], bytes: 3, text: "abc"),
                    .directory([repository, "snapshots"]),
                    .directory([repository, "snapshots", "abc"]),
                    .symlink([repository, "snapshots", "abc", "model.bin"], target: blob, targetVolume: volume),
                    .directory([repository, "snapshots", "def"]),
                    .symlink([repository, "snapshots", "def", "model.bin"], target: blob, targetVolume: volume),
                    .directory([repository, "blobs"]),
                    .file(blob, bytes: 10, identity: .init(device: 61, node: 1)),
                    .file([repository, "blobs", "partial.incomplete"], bytes: 3, identity: .init(device: 61, node: 2)),
                ]
            )
        )
    }

    static func danglingHuggingFaceLink() throws -> HuggingFaceFixture {
        let volume = try VolumeID("volume:synthetic-huggingface-dangling")
        let repository = "models--synthetic--dangling"
        return .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: ModelStoreRoot.huggingFaceDefaultRootID,
                rootVolume: volume,
                environmentEvidence: [],
                entries: [
                    .directory([repository]),
                    .symlink(
                        [repository, "snapshots", "abc", "model.bin"],
                        target: [repository, "blobs", "missing"],
                        targetExists: false,
                        targetVolume: volume
                    ),
                ]
            )
        )
    }

    static func crossVolumeHuggingFaceLink() throws -> HuggingFaceFixture {
        let rootVolume = try VolumeID("volume:synthetic-huggingface-root")
        let foreignVolume = try VolumeID("volume:synthetic-huggingface-foreign")
        let repository = "models--synthetic--cross-volume"
        return .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: ModelStoreRoot.huggingFaceDefaultRootID,
                rootVolume: rootVolume,
                environmentEvidence: [],
                entries: [
                    .directory([repository]),
                    .symlink(
                        [repository, "snapshots", "abc", "model.bin"],
                        target: [repository, "blobs", "sha256"],
                        targetVolume: foreignVolume
                    ),
                ]
            )
        )
    }

    static func unavailableHuggingFaceStore() throws -> HuggingFaceFixture {
        .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: ModelStoreRoot.huggingFaceDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-huggingface-unavailable"),
                environmentEvidence: [],
                rootFault: .unavailableVolume,
                entries: []
            )
        )
    }

    static func budgetHuggingFaceStore() throws -> HuggingFaceFixture {
        .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: ModelStoreRoot.huggingFaceDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-huggingface-budget"),
                environmentEvidence: [],
                entries: [
                    .directory(["models--synthetic--budget"]),
                    .file(["models--synthetic--budget", "blobs", "too-large"], bytes: 2, identity: .init(device: 62, node: 1)),
                ]
            )
        )
    }

    static func cancelledHuggingFaceStore() throws -> HuggingFaceFixture {
        .init(
            root: .defaultHuggingFaceCache(),
            port: .init(
                rootID: ModelStoreRoot.huggingFaceDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-huggingface-cancelled"),
                environmentEvidence: [],
                entries: [.directory(["models--synthetic--cancelled"])]
            )
        )
    }

    static func selectedRootBoundary() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-root")
        let volume = try VolumeID("volume:synthetic-selected-root")
        let root = ModelStoreRoot.explicitlySelected(
            rootID: rootID,
            selection: .validated,
            layout: .selectedRootV1
        )
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: volume,
                environmentEvidence: [],
                entries: [
                    .init(
                        locator: try .init(["Model Store.app"]),
                        kind: .directory,
                        size: .init(logicalBytes: 0),
                        fileIdentity: .observed(.init(device: 52, node: 1)),
                        volume: .observed(volume),
                        text: nil,
                        link: nil,
                        topology: .package
                    ),
                ],
                normalizeEntryMetadata: false
            )
        )
    }

    static func cancelledSelectedRoot() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-root-cancelled")
        let root = ModelStoreRoot.explicitlySelected(
            rootID: rootID,
            selection: .validated,
            layout: .selectedRootV1
        )
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-selected-root-cancelled"),
                environmentEvidence: [],
                entries: [.file(["weights.bin"], bytes: 1, identity: .init(device: 53, node: 1))]
            )
        )
    }

    static func sharedOllamaStore() throws -> OllamaFixture {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:synthetic-ollama-shared")
        let config = validDigest("a")
        let layer = validDigest("b")
        let configFile = try #require(OllamaLayoutContract.v1.blobFileName(for: config))
        let layerFile = try #require(OllamaLayoutContract.v1.blobFileName(for: layer))
        let first = ["manifests", "registry", "synthetic", "demo", "latest"]
        let second = ["manifests", "registry", "synthetic", "demo", "stable"]
        let manifest = OllamaManifestObservation(
            schemaVersion: 2,
            mediaType: "application/vnd.docker.distribution.manifest.v2+json",
            config: .init(mediaType: "application/vnd.ollama.image.config", digest: config, size: 5),
            layers: [.init(mediaType: "application/vnd.ollama.image.model", digest: layer, size: 10)]
        )
        return .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: rootID,
                rootVolume: volume,
                environmentEvidence: [],
                entries: [
                    .directory(["manifests"]),
                    .file(first, bytes: 128, identity: .init(device: 63, node: 1)),
                    .file(second, bytes: 128, identity: .init(device: 63, node: 2)),
                    .directory(["blobs"]),
                    .file(["blobs", configFile], bytes: 5, identity: .init(device: 63, node: 3)),
                    .file(["blobs", layerFile], bytes: 10, identity: .init(device: 63, node: 4)),
                ],
                ollamaManifests: [first: manifest, second: manifest]
            )
        )
    }

    static func missingOllamaBlobStore() throws -> OllamaFixture {
        let digest = validDigest("c")
        let manifestLocator = ["manifests", "registry", "synthetic", "missing", "latest"]
        return .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: ModelStoreRoot.ollamaDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-ollama-missing"),
                environmentEvidence: [],
                entries: [.file(manifestLocator, bytes: 128, identity: .init(device: 64, node: 1))],
                ollamaManifests: [
                    manifestLocator: .init(
                        schemaVersion: 2,
                        mediaType: "application/vnd.docker.distribution.manifest.v2+json",
                        config: .init(mediaType: "application/vnd.ollama.image.config", digest: digest, size: 1),
                        layers: []
                    ),
                ]
            )
        )
    }

    static func unavailableOllamaStore() throws -> OllamaFixture {
        .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: ModelStoreRoot.ollamaDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-ollama-unavailable"),
                environmentEvidence: [],
                rootFault: .unavailableVolume,
                entries: []
            )
        )
    }

    static func crossVolumeOllamaStore() throws -> OllamaFixture {
        let rootVolume = try VolumeID("volume:synthetic-ollama-root")
        let foreignVolume = try VolumeID("volume:synthetic-ollama-foreign")
        let digest = validDigest("d")
        let blobFile = try #require(OllamaLayoutContract.v1.blobFileName(for: digest))
        let manifestLocator = ["manifests", "registry", "synthetic", "cross-volume", "latest"]
        let manifest = OllamaManifestObservation(
            schemaVersion: 2,
            mediaType: "application/vnd.docker.distribution.manifest.v2+json",
            config: .init(mediaType: "application/vnd.ollama.image.config", digest: digest, size: 1),
            layers: []
        )
        return .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: ModelStoreRoot.ollamaDefaultRootID,
                rootVolume: rootVolume,
                environmentEvidence: [],
                entries: [
                    .init(
                        locator: try .init(manifestLocator),
                        kind: .regularFile,
                        size: .init(logicalBytes: 128),
                        fileIdentity: .observed(.init(device: 68, node: 1)),
                        volume: .observed(rootVolume),
                        text: nil,
                        link: nil
                    ),
                    .init(
                        locator: try .init(["blobs", blobFile]),
                        kind: .regularFile,
                        size: .init(logicalBytes: 1),
                        fileIdentity: .observed(.init(device: 68, node: 2)),
                        volume: .observed(foreignVolume),
                        text: nil,
                        link: nil
                    ),
                ],
                ollamaManifests: [manifestLocator: manifest],
                normalizeEntryMetadata: false
            )
        )
    }

    static func budgetOllamaStore() throws -> OllamaFixture {
        let manifestLocator = ["manifests", "registry", "synthetic", "budget", "latest"]
        return .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: ModelStoreRoot.ollamaDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-ollama-budget"),
                environmentEvidence: [],
                entries: [.file(manifestLocator, bytes: 2, identity: .init(device: 65, node: 1))]
            )
        )
    }

    static func cancelledOllamaStore() throws -> OllamaFixture {
        .init(
            root: .defaultOllamaModels(),
            port: .init(
                rootID: ModelStoreRoot.ollamaDefaultRootID,
                rootVolume: try VolumeID("volume:synthetic-ollama-cancelled"),
                environmentEvidence: [],
                entries: [.directory(["manifests"])]
            )
        )
    }

    static func selectedRootForAssociation() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-association")
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-selected-association"),
                environmentEvidence: [],
                entries: [.file(["models", "demo.gguf"], bytes: 5, identity: .init(device: 66, node: 1))]
            )
        )
    }

    static func unavailableSelectedRoot() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-unavailable")
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-selected-unavailable"),
                environmentEvidence: [],
                rootFault: .unavailableVolume,
                entries: []
            )
        )
    }

    static func changedSelectedRoot() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-changed")
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        return .init(
            root: root,
            port: .init(
                rootID: try DeclaredRootID("synthetic-selected-replaced"),
                rootVolume: try VolumeID("volume:synthetic-selected-changed"),
                environmentEvidence: [],
                entries: []
            )
        )
    }

    static func budgetSelectedRoot() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-budget")
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-selected-budget"),
                environmentEvidence: [],
                entries: [.file(["models", "too-large.gguf"], bytes: 2, identity: .init(device: 67, node: 1))]
            )
        )
    }

    static func crossVolumeSelectedRoot() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-cross-volume")
        let rootVolume = try VolumeID("volume:synthetic-selected-root")
        let foreignVolume = try VolumeID("volume:synthetic-selected-foreign")
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: rootVolume,
                environmentEvidence: [],
                entries: [
                    .init(
                        locator: try .init(["models", "foreign.gguf"]),
                        kind: .regularFile,
                        size: .init(logicalBytes: 1),
                        fileIdentity: .observed(.init(device: 69, node: 1)),
                        volume: .observed(foreignVolume),
                        text: nil,
                        link: nil
                    ),
                ],
                normalizeEntryMetadata: false
            )
        )
    }

    static func escapingSelectedRoot() throws -> SelectedRootFixture {
        let rootID = try DeclaredRootID("synthetic-selected-escaping")
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        return .init(
            root: root,
            port: .init(
                rootID: rootID,
                rootVolume: try VolumeID("volume:synthetic-selected-escaping"),
                environmentEvidence: [],
                entries: [.symlink(["models", "escaping"], target: ["outside"])]
            )
        )
    }

    private static func validDigest(_ character: Character) -> String {
        "sha256:" + String(repeating: String(character), count: 64)
    }
}

extension ModelStoreFixtureFactory {
    struct OllamaFixture: Sendable {
        let root: ModelStoreRoot
        let port: ScriptedModelStorePort
    }

    struct SelectedRootFixture: Sendable {
        let root: ModelStoreRoot
        let port: ScriptedModelStorePort
    }
}
