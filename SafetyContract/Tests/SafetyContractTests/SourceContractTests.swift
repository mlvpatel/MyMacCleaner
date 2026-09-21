import Foundation
import Testing
@testable import SafetyContract

@Suite("Source Contract")
struct SourceContractTests {
    @Test
    func safetyPackageOwnsNoNetworkClientCapability() throws {
        for source in try Self.swiftFiles(under: "SafetyContract/Sources/SafetyContract") {
            let contents = try String(contentsOf: source, encoding: .utf8)
            for fragment in ["URLSession", "URLRequest", "http://", "https://", "Network.framework"] {
                #expect(!contents.contains(fragment), "\(source.lastPathComponent) contains \(fragment)")
            }
        }
    }

    @Test
    func scopedServicesUseRedactedDiagnosticsInsteadOfRawPrints() throws {
        let scopedSources = [
            "MyMacCleaner/Core/Services/StartupItemsService.swift"
        ]

        for source in scopedSources {
            let contents = try String(contentsOf: Self.repositoryRoot.appending(path: source), encoding: .utf8)
            #expect(contents.contains("import SafetyContract"), "\(source) must use typed diagnostics")
            #expect(contents.contains("SafetyDiagnosticLogger.emit("), "\(source) must emit a record")
            #expect(!contents.contains("print("), "\(source) still prints raw diagnostics")
            #expect(!contents.contains("debugPrint("), "\(source) still debugPrints raw diagnostics")
            #expect(!contents.contains("NSLog("), "\(source) still uses NSLog")
        }
    }

    @Test
    func sourceGateExposesDiagnosticsNetworkMode() throws {
        let verifier = try String(
            contentsOf: Self.repositoryRoot.appending(path: "scripts/verify-safety-contract.sh"),
            encoding: .utf8
        )

        #expect(verifier.contains("--diagnostics-network-only"))
        #expect(verifier.contains("SC-DIAGNOSTIC-RAW-SINK"))
        #expect(verifier.contains("SC-NETWORK-CAPABILITY"))
        #expect(verifier.contains("run_complete_source_contract"))
        #expect(verifier.contains("validate_diagnostics_and_network"))
        #expect(verifier.contains("scan_mode --source-only"))
        #expect(verifier.contains("\"$product_mode\" == \"--diagnostics-network-only\""))
        #expect(verifier.contains("import[[:space:]]+Network"))
        #expect(verifier.contains("NW(Connection|Listener|PathMonitor)"))
        #expect(verifier.contains("validateNoRawDiagnosticSinks"))
        #expect(verifier.contains("find \"$repository_root/MyMacCleaner\" -type f -name '*.swift'"))
        #expect(verifier.contains("MyMacCleaner/Core/Services/AppState.swift"))

        for mode in Self.composedModes {
            #expect(verifier.contains(mode), "source contract must compose \(mode)")
        }
    }

    @Test
    func diagnosticBoundaryIsClosedAndLoggerOnlyAcceptsRecords() throws {
        let redactor = try Self.readRepositoryFile(
            "SafetyContract/Sources/SafetyContract/RedactingDiagnostic.swift"
        )
        let logger = try Self.readRepositoryFile(
            "MyMacCleaner/Core/Services/SafetyDiagnosticLogger.swift"
        )

        #expect(redactor.contains("enum DiagnosticEventCode"))
        #expect(redactor.contains("public enum RedactingDiagnostic"))
        #expect(!redactor.contains("SensitiveDiagnosticValue"))
        #expect(!redactor.contains("eventCode: String"))
        #expect(logger.contains("static func emit(_ record: RedactedDiagnosticRecord)"))
        #expect(!logger.contains("func log("))
        #expect(!logger.contains("Error"))
    }

    @Test
    func navigationTestHooksAreExplicitAndLocaleIndependent() throws {
        let contentView = try Self.readRepositoryFile("MyMacCleaner/App/ContentView.swift")

        for identifier in Self.navigationIdentifiers {
            #expect(contentView.contains("\"\(identifier)\""))
        }
        #expect(contentView.contains(".accessibilityIdentifier(section.accessibilityIdentifier)"))
    }

    @Test
    func applicationsInventoryHasNoPerInstalledAppNetworkScanner() throws {
        let obsoleteScanner = Self.repositoryRoot.appending(path: "MyMacCleaner/Core/Services/AppUpdateChecker.swift")
        let verifier = try Self.readRepositoryFile("scripts/verify-safety-contract.sh")

        #expect(!FileManager.default.fileExists(atPath: obsoleteScanner.path))
        #expect(!verifier.contains("AppUpdateChecker.swift"))
        #expect(!verifier.contains("appUpdateFeedFetchFailed"))
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func swiftFiles(under relativePath: String) throws -> [URL] {
        let root = repositoryRoot.appending(path: relativePath)
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.pathExtension == "swift" }
    }

    private static func readRepositoryFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appending(path: relativePath), encoding: .utf8)
    }

    private static let composedModes = [
        "--filesystem-only",
        "--system-process-only",
        "--storage-ui-home-only",
        "--storage-ui-disk-browser-only",
        "--storage-ui-space-duplicates-only",
        "--storage-ui-orphan-only",
        "--system-ui-applications-only",
        "--system-ui-performance-only",
        "--system-ui-only"
    ]

    private static let navigationIdentifiers = [
        "navigation.home",
        "navigation.disk-cleaner",
        "navigation.orphaned-files",
        "navigation.duplicates",
        "navigation.performance",
        "navigation.applications",
        "navigation.startup-items",
        "navigation.port-management",
        "navigation.system-health",
        "navigation.permissions"
    ]
}
