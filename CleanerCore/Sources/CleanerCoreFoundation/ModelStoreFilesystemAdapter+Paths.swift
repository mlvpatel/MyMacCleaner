import CleanerCore
import Foundation

// MARK: - Path, Locator, and Identity Helpers

extension ModelStoreFilesystemAdapter {
    func fallbackRootEvidence(
        for root: ModelStoreRoot,
        fault: ModelStoreRootFault
    ) -> ModelStoreRootEvidence {
        .init(
            rootID: root.identity.rootID,
            volume: ModelStoreVolumeIDFallback.value,
            fault: fault,
            environmentEvidence: environmentEvidence[root.identity.rootID] ?? []
        )
    }

    func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func resourceValues(for url: URL) -> URLResourceValues? {
        do {
            return try url.resourceValues(forKeys: Self.resourceKeys)
        } catch {
            return nil
        }
    }

    func shouldDescend(_ values: URLResourceValues) -> Bool {
        values.isDirectory == true
            && values.isSymbolicLink != true
            && values.isAliasFile != true
            && values.isPackage != true
            && values.isMountTrigger != true
    }

    func entryEvidence(
        for url: URL,
        values: URLResourceValues,
        rootURL: URL
    ) throws -> ModelStoreEntryEvidence {
        let locator = try relativeLocator(for: url.standardizedFileURL, rootURL: rootURL)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let identity = try identityEvidence(from: attributes)
        let volume = volumeEvidence(for: url).map(EvidenceValue.observed) ?? .unavailable
        let topology = topology(from: values)

        if values.isSymbolicLink == true {
            return .init(
                locator: locator,
                kind: .symbolicLink,
                size: .init(logicalBytes: 0),
                fileIdentity: identity,
                volume: volume,
                text: nil,
                link: nil,
                topology: topology
            )
        }

        if values.isDirectory == true {
            return .init(
                locator: locator,
                kind: .directory,
                size: .init(logicalBytes: 0),
                fileIdentity: identity,
                volume: volume,
                text: nil,
                link: nil,
                topology: topology
            )
        }

        return .init(
            locator: locator,
            kind: .regularFile,
            size: .init(logicalBytes: values.fileSize.map(EvidenceValue.observed) ?? .unavailable),
            fileIdentity: identity,
            volume: volume,
            text: nil,
            link: nil,
            topology: topology
        )
    }

    func topology(from values: URLResourceValues) -> ModelStoreEntryTopology {
        if values.isPackage == true { return .package }
        if values.isMountTrigger == true { return .mountTrigger }
        if values.isAliasFile == true { return .alias }
        return .ordinary
    }

    func url(for locator: ModelStoreLocator, in root: ModelStoreRoot, allowFinalSymlink: Bool) -> URL? {
        guard let rootURL = rootURLs[root.identity.rootID] else { return nil }
        var candidate = rootURL
        for (index, component) in locator.components.enumerated() {
            candidate = candidate.appendingPathComponent(component, isDirectory: false)
            let isFinal = index == locator.components.count - 1
            guard candidate.standardizedFileURL.path.hasPrefix(rootURL.path + "/"),
                  (allowFinalSymlink && isFinal || kindEvidence(for: candidate) != .observed(.symbolicLink))
            else {
                return nil
            }
        }
        guard candidate.standardizedFileURL.path.hasPrefix(rootURL.path + "/") else {
            return nil
        }
        return candidate.standardizedFileURL
    }

    func relativeLocator(for url: URL, rootURL: URL) throws -> ModelStoreLocator {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath != rootPath,
              itemPath.hasPrefix(rootPath + "/")
        else {
            throw EvidenceValidationError.invalidRelativeLocator
        }
        return try .init(itemPath.dropFirst(rootPath.count + 1).split(separator: "/").map(String.init))
    }

    func depth(for url: URL, rootURL: URL) throws -> Int {
        try relativeLocator(for: url.standardizedFileURL, rootURL: rootURL).components.count
    }

    func identityEvidence(
        from attributes: [FileAttributeKey: Any]
    ) throws -> EvidenceValue<FileIdentityEvidence> {
        guard let device = try numericAttribute(.systemNumber, in: attributes),
              let node = try numericAttribute(.systemFileNumber, in: attributes)
        else {
            return .unavailable
        }
        return .observed(.init(device: device, node: node))
    }

    func identityEvidence(for url: URL) -> EvidenceValue<FileIdentityEvidence> {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            return .unavailable
        }
        do {
            return try identityEvidence(from: attributes)
        } catch {
            return .unavailable
        }
    }

    func observedIdentity(for url: URL) -> FileIdentityEvidence? {
        switch identityEvidence(for: url) {
        case .observed(let identity):
            return identity
        case .unknown, .unavailable:
            return nil
        }
    }
}
