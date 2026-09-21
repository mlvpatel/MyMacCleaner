public struct DetectorSelection: Equatable, Sendable {
    public let id: DetectorID
    public let version: DetectorVersion

    public init(id: DetectorID, version: DetectorVersion) {
        self.id = id
        self.version = version
    }
}

public enum DetectorRegistryError: Error, Equatable, Sendable {
    case emptyRegistry
    case duplicateRegistration
    case invalidVersion
    case unknownDetector
    case unsupportedVersion
}

struct DetectorRegistration: Sendable {
    let selection: DetectorSelection
    let detector: any LocalDetector

    init(detector: any LocalDetector) {
        selection = .init(id: detector.identifier, version: detector.version)
        self.detector = detector
    }
}

struct DetectorRegistry: Sendable {
    let availableSelections: [DetectorSelection]
    private let detectors: [DetectorKey: any LocalDetector]

    init(registrations: [DetectorRegistration]) throws {
        guard !registrations.isEmpty else { throw DetectorRegistryError.emptyRegistry }

        var keyedDetectors: [DetectorKey: any LocalDetector] = [:]
        for registration in registrations {
            guard DetectorKey.isSemanticVersion(registration.selection.version.value) else {
                throw DetectorRegistryError.invalidVersion
            }

            let key = DetectorKey(selection: registration.selection)
            guard keyedDetectors[key] == nil else {
                throw DetectorRegistryError.duplicateRegistration
            }
            keyedDetectors[key] = registration.detector
        }

        detectors = keyedDetectors
        availableSelections = keyedDetectors.keys
            .sorted()
            .map { .init(id: $0.id, version: $0.version) }
    }

    func resolve(_ selection: DetectorSelection) throws -> any LocalDetector {
        guard DetectorKey.isSemanticVersion(selection.version.value) else {
            throw DetectorRegistryError.invalidVersion
        }

        let key = DetectorKey(selection: selection)
        if let detector = detectors[key] {
            return detector
        }

        let hasDetectorID = detectors.keys.contains { $0.id == selection.id }
        throw hasDetectorID
            ? DetectorRegistryError.unsupportedVersion : DetectorRegistryError.unknownDetector
    }
}

private struct DetectorKey: Hashable, Comparable, Sendable {
    let id: DetectorID
    let version: DetectorVersion

    init(selection: DetectorSelection) {
        id = selection.id
        version = selection.version
    }

    static func < (lhs: DetectorKey, rhs: DetectorKey) -> Bool {
        if lhs.id.value != rhs.id.value {
            return lhs.id.value < rhs.id.value
        }
        return lhs.version.value < rhs.version.value
    }

    static func isSemanticVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }
}
