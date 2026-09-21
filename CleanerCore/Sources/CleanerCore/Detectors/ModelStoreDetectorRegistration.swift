public enum ModelStoreDetectorRegistration {
    public static let huggingFaceSelection = DetectorSelection(
        id: ModelStoreDetector.huggingFaceV1.id,
        version: ModelStoreDetector.huggingFaceV1.version
    )

    public static let ollamaSelection = DetectorSelection(
        id: ModelStoreDetector.ollamaV1.id,
        version: ModelStoreDetector.ollamaV1.version
    )

    public static let selectedRootSelection = DetectorSelection(
        id: ModelStoreDetector.selectedRootV1.id,
        version: ModelStoreDetector.selectedRootV1.version
    )

    static let registrations: [DetectorRegistration] = [
        .init(detector: HuggingFaceInventoryDetector()),
        .init(detector: OllamaInventoryDetector()),
        .init(detector: SelectedRootInventoryDetector())
    ]
}

private struct OllamaInventoryDetector: LocalDetector {
    let identifier = ModelStoreDetector.ollamaV1.id
    let version = ModelStoreDetector.ollamaV1.version

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        guard observation.locator.components.first == "manifests"
            || observation.locator.components.first == "blobs"
        else { return .success(nil) }
        do {
            return .success(try Finding(
                detectorID: identifier,
                detectorVersion: version,
                provenance: .filesystemObservation,
                observation: observation,
                declaredRoot: request.declaredRoot,
                observationInstant: clockReading.observationInstant
            ))
        } catch let error as EvidenceValidationError {
            return .failure(error)
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}

/// This registration intentionally never guesses a LM Studio root. A later
/// caller must supply `ModelStoreSelectedRootToken.validated` to the generic
/// selected-root inventory before any observation starts.
private struct SelectedRootInventoryDetector: LocalDetector {
    let identifier = ModelStoreDetector.selectedRootV1.id
    let version = ModelStoreDetector.selectedRootV1.version

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        .success(nil)
    }
}

private struct HuggingFaceInventoryDetector: LocalDetector {
    let identifier = ModelStoreDetector.huggingFaceV1.id
    let version = ModelStoreDetector.huggingFaceV1.version

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        guard observation.locator.components.first?.hasPrefix("models--") == true else {
            return .success(nil)
        }

        do {
            return .success(
                try Finding(
                    detectorID: identifier,
                    detectorVersion: version,
                    provenance: .filesystemObservation,
                    observation: observation,
                    declaredRoot: request.declaredRoot,
                    observationInstant: clockReading.observationInstant
                ))
        } catch let error as EvidenceValidationError {
            return .failure(error)
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}
