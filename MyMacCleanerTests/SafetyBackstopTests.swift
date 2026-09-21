import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Applications Read-Only Tests

@Suite("Applications Read-Only Tests")
struct ApplicationsReadOnlyTests {

    private let sourcePaths = [
        "MyMacCleaner/Features/Applications/ApplicationsViewModel.swift",
        "MyMacCleaner/Features/Applications/ApplicationsView.swift",
        "MyMacCleaner/Features/Applications/Components/AppCard.swift",
        "MyMacCleaner/Features/Applications/Components/HomebrewCaskRow.swift"
    ]

    private let forbiddenRoutes: Set<String> = [
        "AuthorizationService",
        "/bin/rm",
        "trashItem",
        "prepareUninstall",
        "upgradeCask",
        "cleanupHomebrew",
        "Process(",
        "applications.updates.download"
    ]

    @Test("Applications inventory starts with read-only evidence state")
    @MainActor
    func applicationsInventoryStartsWithReadOnlyEvidenceState() async throws {
        let viewModel = ApplicationsViewModel()

        #expect(viewModel.filteredApps.isEmpty)
        #expect(viewModel.isHomebrewInstalled == false)
        #expect(viewModel.isHomebrewInventoryUnavailable == false)
    }

    @Test("Applications source backstop covers every retained component and forbidden route")
    func applicationsSourceBackstopCoversComponentsAndForbiddenRoutes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for sourcePath in sourcePaths {
            let source = try String(contentsOf: repositoryRoot.appendingPathComponent(sourcePath))

            for forbiddenRoute in forbiddenRoutes {
                #expect(
                    !source.contains(forbiddenRoute),
                    "\(sourcePath) must not contain \(forbiddenRoute)"
                )
            }
        }

        let verifierPath = repositoryRoot.appendingPathComponent("scripts/verify-safety-contract.sh")
        let verifier = try String(contentsOf: verifierPath)
        for sourcePath in sourcePaths {
            #expect(verifier.contains(sourcePath), "Verifier must cover \(sourcePath)")
        }

        let retiredUpdateRow = repositoryRoot.appendingPathComponent(
            "MyMacCleaner/Features/Applications/Components/UpdateRow.swift"
        )
        #expect(verifier.contains("MyMacCleaner/Features/Applications/Components/UpdateRow.swift"))
        #expect(!FileManager.default.fileExists(atPath: retiredUpdateRow.path))
    }

    @Test("Application version labels omit missing or blank metadata")
    func applicationVersionLabelsOmitMissingOrBlankMetadata() async throws {
        #expect(AppInfo.displayVersion(for: nil) == nil)
        #expect(AppInfo.displayVersion(for: "   ") == nil)
        #expect(AppInfo.displayVersion(for: "1.2.3") == "v1.2.3")
    }
}

// MARK: - Safety Source Backstops

@Suite("Safety Source Backstop Tests")
struct SafetySourceBackstopTests {
    @Test("Former action screens keep read-only test hooks and no destructive identifiers")
    func formerActionScreensRemainReadOnlyInSource() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = [
            "MyMacCleaner/App/ContentView.swift",
            "MyMacCleaner/Features/Home/HomeView.swift",
            "MyMacCleaner/Features/DiskCleaner/DiskCleanerView.swift",
            "MyMacCleaner/Features/Duplicates/DuplicatesView.swift",
            "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesView.swift",
            "MyMacCleaner/Features/Applications/ApplicationsView.swift",
            "MyMacCleaner/Features/Performance/PerformanceView.swift",
            "MyMacCleaner/Features/StartupItems/StartupItemsView.swift",
            "MyMacCleaner/Features/PortManagement/PortManagementView.swift"
        ]
        let forbiddenIdentifiers = [
            "onKill",
            "prepareKill",
            "confirmKill",
            "prepareUninstall",
            "upgradeCask",
            "removeStartupItem",
            "setItemEnabled",
            "emptyTrash"
        ]

        for sourcePath in sources {
            let source = try String(contentsOf: repositoryRoot.appendingPathComponent(sourcePath))
            for identifier in forbiddenIdentifiers {
                #expect(!source.contains(identifier), "\(sourcePath) must not retain \(identifier)")
            }
        }

        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MyMacCleaner/App/ContentView.swift")
        )
        for identifier in Self.requiredNavigationIdentifiers {
            #expect(contentView.contains("\"\(identifier)\""))
        }
        #expect(contentView.contains(".accessibilityIdentifier(section.accessibilityIdentifier)"))
    }

    private static let requiredNavigationIdentifiers = [
        "navigation.home",
        "navigation.disk-cleaner",
        "navigation.space-lens",
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

// MARK: - Retired Legacy Scanner Tests

@Suite("Retired Legacy Scanner Tests")
struct RetiredLegacyScannerTests {
    @Test("Legacy FileScanner stays retired; scans route through CleanerCore")
    func legacyFileScannerIsRetired() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let retired = root.appendingPathComponent("MyMacCleaner/Core/Services/FileScanner.swift")

        #expect(!FileManager.default.fileExists(atPath: retired.path))
    }
}

@Suite("Receipt History Flow Tests")
struct ReceiptHistoryFlowTests {
    @Test("Receipt bridge source rejects URL authority and restore routes")
    func receiptBridgeSourceRejectsURLAuthorityAndRestoreRoutes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "MyMacCleaner/Core/Services/CleanerCoreBridge.swift"
            )
        )
        #expect(source.contains("struct ReceiptSession"))
        #expect(source.contains("func reveal(receiptID: String, itemID: String)"))
        #expect(source.contains("func delete(receiptID: String)"))
        #expect(!source.contains("emptyTrash"))
        #expect(!source.contains("restoreItem"))
        #expect(!source.contains("func reveal(url: URL)"))
        #expect(!source.contains("func delete(url: URL)"))
    }
}

// MARK: - Update Capability Tests

@Suite("Update Capability Tests")
struct UpdateCapabilityTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("The only update capability is a visible, input-free unavailable state")
    func capabilityIsUnavailable() {
        #expect(UpdateCapability.current == .unavailable)
        #expect(L(UpdateCapability.current.titleKey) != UpdateCapability.current.titleKey)
        #expect(L(UpdateCapability.current.messageKey) != UpdateCapability.current.messageKey)
    }

    @Test("Sparkle, the custom updater, and the appcast stay removed")
    func updateStackStaysRemoved() throws {
        let retired = [
            "MyMacCleaner/Core/Services/UpdateManager.swift",
            "MyMacCleaner/Core/Design/UpdateAvailableButton.swift",
            "appcast.xml",
        ]
        for path in retired {
            #expect(!FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path), "\(path) returned")
        }

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MyMacCleaner.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        #expect(!project.contains("Sparkle"))
        #expect(!project.contains("SPARKLE_"))
        #expect(project.contains("SWIFT_STRICT_CONCURRENCY = complete;"))
        #expect(project.contains("baseConfigurationReference = C0F1600000000000000000A1 /* Signing.xcconfig */;"))
    }

    @Test("Committed signing defaults are ad hoc and carry no team")
    func signingDefaultsAreAdHoc() throws {
        let config = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/Signing.xcconfig"),
            encoding: .utf8
        )
        #expect(config.contains("CODE_SIGN_IDENTITY = -"))
        #expect(config.contains("DEVELOPMENT_TEAM =\n"))
        #expect(config.contains("#include? \"Signing.local.xcconfig\""))
    }
}
