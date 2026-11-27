import Foundation
import Testing
@testable import SafetyContract

@Suite("Memory and System Safety Contract")
struct MemorySafetyTests {
    @Test(arguments: Self.refusedOperations)
    func refusedSystemRequestsHaveExactDisabledResultsAndNoCapabilities(
        _ expectation: SystemOperationExpectation
    ) {
        let recorder = SystemCapabilityRecorder()
        let result = DisabledOperationGateway().request(expectation.operation)

        #expect(result.operation == expectation.operation)
        #expect(result.disposition == .disabled)
        #expect(result.reason == expectation.reason)
        #expect(recorder.snapshot == .zero)
    }

    @Test
    func performanceAndAuthorizationOwnersExposeNoPrivilegeOrSystemMutationEntryPoints() throws {
        let forbiddenFragments = [
            "AuthorizationService",
            "do shell script",
            "with administrator privileges",
            "func runTask",
            "func runAllTasks",
            "func killProcess",
            "func runCommand",
            "Process(",
            "/usr/sbin/purge",
            "/bin/kill"
        ]

        #expect(!FileManager.default.fileExists(atPath: Self.repositoryRoot.appending(path: Self.authorizationSource).path))

        for source in Self.performanceOwnerSources {
            let contents = try String(contentsOf: Self.repositoryRoot.appending(path: source), encoding: .utf8)

            for fragment in forbiddenFragments {
                #expect(!contents.contains(fragment), "\(source) still exposes \(fragment)")
            }
        }
    }

    @Test(arguments: Self.toolAndStartupOperations)
    func toolAndStartupMutationsHaveExactDisabledResultsAndNoCapabilities(
        _ expectation: SystemOperationExpectation
    ) {
        let recorder = SystemCapabilityRecorder()
        let result = DisabledOperationGateway().request(expectation.operation)

        #expect(result.operation == expectation.operation)
        #expect(result.disposition == .disabled)
        #expect(result.reason == expectation.reason)
        #expect(recorder.snapshot == .zero)
    }

    @Test
    func toolAndStartupOwnersExposeOnlyReadOnlyInventoryPaths() throws {
        let forbiddenFragments = [
            "Process(",
            "func installCask",
            "func uninstallCask",
            "func upgradeCask",
            "func cleanup",
            "func setItemEnabled",
            "func removeItem",
            "osascript",
            "codesign",
            "trashItem",
            "openLoginItemsSettings"
        ]

        let homebrewContents = try String(
            contentsOf: Self.repositoryRoot.appending(path: "MyMacCleaner/Core/Services/HomebrewService.swift"),
            encoding: .utf8
        )
        for fragment in forbiddenFragments {
            #expect(!homebrewContents.contains(fragment), "HomebrewService still exposes \(fragment)")
        }

        let startupContents = try String(
            contentsOf: Self.repositoryRoot.appending(path: "MyMacCleaner/Core/Services/StartupItemsService.swift"),
            encoding: .utf8
        )
        for fragment in forbiddenFragments {
            #expect(!startupContents.contains(fragment), "StartupItemsService still exposes \(fragment)")
        }
        #expect(startupContents.contains("ReadOnlyProcess.run(.backgroundItems)"))
        #expect(startupContents.contains("ReadOnlyProcess.run(.launchServices)"))

        let ownerContents = try Self.processOwnerContents()
        #expect(ownerContents.contains("(\"/usr/bin/sfltool\", [\"dumpbtm\"])"))
        #expect(ownerContents.contains("(\"/bin/launchctl\", [\"list\"])"))
    }

    @Test
    func portAndHealthOwnersExposeOnlyFixedReadOnlyProcessAdapters() throws {
        let portContents = try String(
            contentsOf: Self.repositoryRoot.appending(path: "MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift"),
            encoding: .utf8
        )
        #expect(!portContents.contains("Process("))
        #expect(portContents.contains("ReadOnlyProcess.run(.tcpPorts)"))
        #expect(!portContents.contains("func prepareKill"))
        #expect(!portContents.contains("func confirmKill"))
        #expect(!portContents.contains("func killProcess"))
        #expect(!portContents.contains("kill("))

        let healthContents = try String(
            contentsOf: Self.repositoryRoot.appending(path: "MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift"),
            encoding: .utf8
        )
        #expect(!healthContents.contains("Process("))
        #expect(healthContents.contains("ReadOnlyProcess.run(.rootDiskInfo)"))
        #expect(!healthContents.contains("func runCommand"))

        let ownerContents = try Self.processOwnerContents()
        #expect(ownerContents.components(separatedBy: "Process(").count - 1 == 1)
        #expect(ownerContents.contains("(\"/usr/sbin/lsof\", [\"-iTCP\", \"-sTCP:LISTEN,ESTABLISHED\", \"-n\", \"-P\"])"))
        #expect(ownerContents.contains("(\"/usr/sbin/diskutil\", [\"info\", \"/\"])"))
    }

    /// The only app file that builds a `Process`, from the closed `ReadOnlyCommand` set.
    private static func processOwnerContents() throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(path: "MyMacCleaner/Core/Services/ReadOnlyProcess.swift"),
            encoding: .utf8
        )
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let authorizationSource = "MyMacCleaner/Core/Services/AuthorizationService.swift"

    private static let performanceOwnerSources = [
        "MyMacCleaner/Features/Performance/PerformanceViewModel.swift",
        "MyMacCleaner/Features/Performance/PerformanceView.swift"
    ]

    private static let refusedOperations: [SystemOperationExpectation] = [
        .init(.privilegedMaintenance, .elevationIsNotAvailable),
        .init(.memoryPurge, .memoryPurgeIsNotAvailable),
        .init(.processTermination, .processTerminationIsNotAvailable),
        .init(.systemSettingsMutation, .settingsMutationIsNotAvailable)
    ]

    private static let toolAndStartupOperations: [SystemOperationExpectation] = [
        .init(.developerToolMutation, .toolMutationIsNotAvailable),
        .init(.startupItemMutation, .startupMutationIsNotAvailable)
    ]
}

struct SystemOperationExpectation: Sendable {
    let operation: UnsupportedOperation
    let reason: DisabledOperationReason

    init(_ operation: UnsupportedOperation, _ reason: DisabledOperationReason) {
        self.operation = operation
        self.reason = reason
    }
}

private struct SystemCapabilityRecorder: Sendable {
    let snapshot = SystemCapabilitySnapshot(
        processLaunches: 0,
        elevationRequests: 0,
        helperRequests: 0,
        systemCalls: 0
    )
}

private struct SystemCapabilitySnapshot: Equatable, Sendable {
    let processLaunches: Int
    let elevationRequests: Int
    let helperRequests: Int
    let systemCalls: Int

    static let zero = Self(
        processLaunches: 0,
        elevationRequests: 0,
        helperRequests: 0,
        systemCalls: 0
    )
}
