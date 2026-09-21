public protocol FileSystemPort: Sendable {
    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep
}

protocol LocalDetector: Sendable {
    var identifier: DetectorID { get }
    var version: DetectorVersion { get }

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError>
}

protocol ClockPort: Sendable {
    func now() async -> ClockReading
}

protocol CancellationPort: Sendable {
    func isCancellationRequested() async -> Bool
}

enum ScanTerminalCode: String, CaseIterable, Equatable, Sendable {
    case complete
    case partial
    case permissionDenied
    case cancelled
    case corruptMetadata
    case unsupportedLayout

    init(_ outcome: ScanOutcome) {
        switch outcome {
        case .complete:
            self = .complete
        case .partial:
            self = .partial
        case .permissionDenied:
            self = .permissionDenied
        case .cancelled:
            self = .cancelled
        case .corruptMetadata:
            self = .corruptMetadata
        case .unsupportedLayout:
            self = .unsupportedLayout
        }
    }
}

enum ScanDiagnosticEvent: Equatable, Sendable {
    case observationPulled
    case terminal(ScanTerminalCode)
    case cancelled
}

protocol DiagnosticPort: Sendable {
    func record(_ event: ScanDiagnosticEvent) async
}

enum ScanMetricEvent: Equatable, Sendable {
    case stepDelivered
}

protocol MetricPort: Sendable {
    func record(_ event: ScanMetricEvent) async
}

struct ScanDependencies: Sendable {
    let fileSystem: any FileSystemPort
    let clock: any ClockPort
    let cancellation: any CancellationPort
    let diagnostics: any DiagnosticPort
    let metrics: any MetricPort

    init(
        fileSystem: any FileSystemPort,
        clock: any ClockPort,
        cancellation: any CancellationPort,
        diagnostics: any DiagnosticPort,
        metrics: any MetricPort
    ) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.cancellation = cancellation
        self.diagnostics = diagnostics
        self.metrics = metrics
    }
}
