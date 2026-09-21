import Testing
import Foundation
@testable import SafetyContract

@Suite("Redacting Diagnostic Contract")
struct RedactionTests {
    @Test
    func hostileFixtureLeavesOnlyCodesMarkersAndCounts() {
        let fixture = Self.hostileFixture
        let record = RedactingDiagnostic.record(
            event: .updateManagerNetworkFailed,
            sensitiveClasses: fixture.map(\.sensitiveClass)
        )
        let rendered = record.rendered

        #expect(record.eventCode == .updateManagerNetworkFailed)
        #expect(record.totalRedactionCount == fixture.count)
        #expect(record.markerCategories == SensitiveDiagnosticClass.allCases.map(\.rawValue))

        for value in fixture.map(\.rawValue) + Self.forbiddenFragments {
            #expect(!rendered.contains(value), "rendered diagnostic leaked sensitive fixture data")
        }
        #expect(rendered.contains("UPDATE_MANAGER_NETWORK_FAILED"))
        #expect(rendered.contains("path=1"))
        #expect(rendered.contains("receipt=1"))
    }

    @Test(arguments: SensitiveDiagnosticClass.allCases)
    func everySensitiveClassIsCountedWithoutRawValue(_ sensitiveClass: SensitiveDiagnosticClass) {
        let rawValue = "private-\(sensitiveClass.rawValue)-workspace-item"
        let record = RedactingDiagnostic.record(
            event: .fileScannerPathSkipped,
            sensitiveClasses: [sensitiveClass]
        )

        #expect(record.totalRedactionCount == 1)
        #expect(record.redactionCounts[sensitiveClass] == 1)
        #expect(record.markerCategories == [sensitiveClass.rawValue])
        #expect(!record.rendered.contains(rawValue))
        #expect(!record.rendered.contains("workspace-item"))
    }

    @Test
    func countAndRenderingAreBounded() {
        let record = RedactingDiagnostic.record(
            event: .fileScannerCategorySkipped,
            sensitiveClasses: Array(repeating: .path, count: 500)
        )

        #expect(record.totalRedactionCount == RedactedDiagnosticRecord.maximumCountPerClass)
        #expect(record.rendered.count <= RedactedDiagnosticRecord.maximumRenderedLength)
        #expect(record.rendered.contains("path=\(RedactedDiagnosticRecord.maximumCountPerClass)"))
    }

    @Test
    func scannerAndStartupFailuresUseTypedRecordsWithoutRawSinks() throws {
        let scopedSources = [
            (
                "MyMacCleaner/Core/Services/StartupItemsService.swift",
                [".startupBackgroundItemsUnavailable", ".startupLaunchctlItemsUnavailable"]
            )
        ]

        for (path, events) in scopedSources {
            let source = try String(contentsOf: Self.repositoryRoot.appending(path: path), encoding: .utf8)
            #expect(source.contains("import SafetyContract"))
            #expect(!source.contains("print("))
            #expect(!source.contains("debugPrint("))
            #expect(!source.contains("NSLog("))
            for event in events {
                #expect(source.contains(event))
            }
        }
    }

    private static let hostileFixture = [
        FixtureValue(.path, "/private/test-user/Library/Caches/model-store"),
        FixtureValue(.localName, "private-model-workspace"),
        FixtureValue(.credential, "synthetic-token-value"),
        FixtureValue(.appcastBody, "<rss><item><version>999</version></item></rss>"),
        FixtureValue(.command, "/usr/bin/example-command --private-flag"),
        FixtureValue(.error, "ExampleDomain Code=-1 private-detail"),
        FixtureValue(.receipt, "{\"receipt\":\"private-value\",\"path\":\"/private/test-user\"}")
    ]

    private static let forbiddenFragments = [
        "/private/test-user",
        "private-model-workspace",
        "synthetic-token-value",
        "<rss",
        "example-command",
        "ExampleDomain",
        "\"receipt\""
    ]

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct FixtureValue: Sendable {
    let sensitiveClass: SensitiveDiagnosticClass
    let rawValue: String

    init(_ sensitiveClass: SensitiveDiagnosticClass, _ rawValue: String) {
        self.sensitiveClass = sensitiveClass
        self.rawValue = rawValue
    }
}
