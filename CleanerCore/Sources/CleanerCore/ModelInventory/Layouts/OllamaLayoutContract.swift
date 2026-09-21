/// Inert provenance for a source inspected while defining a local recognizer.
/// This value is descriptive only: it cannot construct or fetch a web address.
public struct OllamaPinnedSource: Equatable, Sendable {
    public enum Scheme: String, Equatable, Sendable {
        case https
    }

    public let scheme: Scheme
    public let host: String
    public let path: String

    public init(scheme: Scheme, host: String, path: String) {
        self.scheme = scheme
        self.host = host
        self.path = path
    }
}

/// Offline recognizer evidence for the local Ollama model-store layout.
///
/// Checked 2026-08-24 against the authoritative `main` commit below. These
/// values are inert development-time evidence: runtime code does not fetch the
/// web addresses or invoke an Ollama executable or service.
public struct OllamaLayoutContract: Equatable, Sendable {
    public let recognizerVersion: String
    public let sourceCommit: String
    public let checkedDate: String
    public let manifestSource: OllamaPinnedSource
    public let pathsSource: OllamaPinnedSource
    public let faqSource: OllamaPinnedSource
    public let schemaVersion: Int
    public let manifestMediaType: String
    public let configMediaType: String
    /// A deliberately conservative recognizer allowlist, not an assertion that
    /// Ollama will never introduce other descriptor media types. Unknown types
    /// fail closed until a later contract pins and tests their source evidence.
    public let layerMediaTypes: Set<String>
    /// Primary-source provenance for every media family the recognizer accepts.
    public let layerMediaTypeSources: [String: OllamaPinnedSource]
    public let manifestPathComponentCount: Int
    public let manifestsRoot: ModelStoreLocator
    public let blobsRoot: ModelStoreLocator
    public let digestValidationExpression: String

    public init(
        recognizerVersion: String,
        sourceCommit: String,
        checkedDate: String,
        manifestSource: OllamaPinnedSource,
        pathsSource: OllamaPinnedSource,
        faqSource: OllamaPinnedSource,
        schemaVersion: Int,
        manifestMediaType: String,
        configMediaType: String,
        layerMediaTypes: Set<String>,
        layerMediaTypeSources: [String: OllamaPinnedSource],
        manifestPathComponentCount: Int,
        manifestsRoot: ModelStoreLocator,
        blobsRoot: ModelStoreLocator,
        digestValidationExpression: String
    ) {
        self.recognizerVersion = recognizerVersion
        self.sourceCommit = sourceCommit
        self.checkedDate = checkedDate
        self.manifestSource = manifestSource
        self.pathsSource = pathsSource
        self.faqSource = faqSource
        self.schemaVersion = schemaVersion
        self.manifestMediaType = manifestMediaType
        self.configMediaType = configMediaType
        self.layerMediaTypes = layerMediaTypes
        self.layerMediaTypeSources = layerMediaTypeSources
        self.manifestPathComponentCount = manifestPathComponentCount
        self.manifestsRoot = manifestsRoot
        self.blobsRoot = blobsRoot
        self.digestValidationExpression = digestValidationExpression
    }

    /// The sole accepted `manifest.BlobsPath` local-name transformation.
    public func blobFileName(for digest: String) -> String? {
        guard let normalized = normalizedDigest(digest) else { return nil }
        return "sha256-\(normalized)"
    }

    /// Both `sha256:<hex>` and `sha256-<hex>` are accepted by Ollama's pinned
    /// `BlobsPath`; all non-SHA-256 and malformed values are rejected.
    public func normalizedDigest(_ digest: String) -> String? {
        let prefix: String
        if digest.hasPrefix("sha256:") {
            prefix = "sha256:"
        } else if digest.hasPrefix("sha256-") {
            prefix = "sha256-"
        } else {
            return nil
        }
        let hexadecimal = String(digest.dropFirst(prefix.count))
        guard hexadecimal.count == 64,
              hexadecimal.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value)
                      || (65...70).contains(scalar.value)
                      || (97...102).contains(scalar.value)
              })
        else {
            return nil
        }
        return hexadecimal
    }

    public func accepts(config: OllamaLayerObservation, layers: [OllamaLayerObservation]) -> Bool {
        config.mediaType == configMediaType
            && layers.allSatisfy { layerMediaTypes.contains($0.mediaType) }
    }

    private static func contractLocator(_ components: [String]) -> ModelStoreLocator {
        do {
            return try ModelStoreLocator(components)
        } catch {
            preconditionFailure("invalid package-owned layout locator")
        }
    }

    public static let v1 = OllamaLayoutContract(
        recognizerVersion: "ollama-layout-v1",
        sourceCommit: "fb30760996871fa9460115c753afd2c60d4ab0f7",
        checkedDate: "2026-08-24",
        manifestSource: .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/manifest/manifest.go"),
        pathsSource: .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/manifest/paths.go"),
        faqSource: .init(scheme: .https, host: "docs.ollama.com", path: "faq"),
        schemaVersion: 2,
        manifestMediaType: "application/vnd.docker.distribution.manifest.v2+json",
        configMediaType: "application/vnd.ollama.image.config",
        layerMediaTypes: [
            "application/vnd.ollama.image.adapter",
            "application/vnd.ollama.image.draft",
            "application/vnd.ollama.image.embed",
            "application/vnd.ollama.image.license",
            "application/vnd.ollama.image.messages",
            "application/vnd.ollama.image.model",
            "application/vnd.ollama.image.params",
            "application/vnd.ollama.image.prompt",
            "application/vnd.ollama.image.projector",
            "application/vnd.ollama.image.system",
            "application/vnd.ollama.image.template",
            "application/vnd.ollama.image.tensor",
        ],
        layerMediaTypeSources: [
            "application/vnd.ollama.image.adapter": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.draft": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/manifest/layer.go"),
            "application/vnd.ollama.image.embed": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.license": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.messages": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.model": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.params": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.prompt": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.projector": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.system": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.template": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/server/images.go"),
            "application/vnd.ollama.image.tensor": .init(scheme: .https, host: "github.com", path: "ollama/ollama/blob/fb30760996871fa9460115c753afd2c60d4ab0f7/manifest/layer.go"),
        ],
        manifestPathComponentCount: 5,
        manifestsRoot: contractLocator(["manifests"]),
        blobsRoot: contractLocator(["blobs"]),
        digestValidationExpression: "^sha256[:-][0-9a-fA-F]{64}$"
    )
}
