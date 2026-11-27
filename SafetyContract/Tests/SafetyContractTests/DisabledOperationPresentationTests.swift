import Foundation
import Testing
@testable import SafetyContract

@Suite("Disabled Operation Presentation Contract")
struct DisabledOperationPresentationTests {
    @Test
    func storagePresentationTableCoversEveryStorageOperationFamily() {
        #expect(Self.storageExpectations.count == 8)

        for expectation in Self.storageExpectations {
            let result = DisabledOperationGateway().request(expectation.operation)
            let presentation = DisabledOperationPresentation.forOperation(expectation.operation)

            #expect(result.operation == expectation.operation)
            #expect(result.reason == expectation.reason)
            #expect(presentation.tone == .informational)
            #expect(presentation.title == expectation.title)
            #expect(presentation.message == expectation.message)
            #expect(presentation.actionTitle == "Learn why")
            #expect(expectation.isDestructive == false)
            #expect(expectation.accessibilityID == "safety.notice.\(expectation.code)")
            #expect(expectation.payload == nil)
        }
    }

    @Test
    func appPresenterUsesClosedStorageIdentitiesAndRealCallers() throws {
        let presenter = try Self.readRepositoryFile(
            "MyMacCleaner/Core/Design/SafetyNoticePresenter.swift"
        )
        let normalizedPresenter = Self.normalizedWhitespace(presenter)

        #expect(!presenter.contains("code: String"))
        #expect(!presenter.contains("func notice(for operation: UnsupportedOperation"))
        #expect(!presenter.contains("spaceLensStorageReviewNotice"))
        #expect(!presenter.contains("spaceLensReviewedPlanCleanup"))
        #expect(
            normalizedPresenter.contains(
                "private enum StorageSafetyNoticeIdentity: String, Sendable"
            )
        )
        #expect(
            normalizedPresenter.contains(
                "private func notice(for identity: StorageSafetyNoticeIdentity) -> SafetyNoticeState"
            )
        )
        #expect(normalizedPresenter.contains("gateway.request(identity.operation)"))

        // The read-only inventories route to the Experience instead of a "coming later" notice,
        // so the reviewed-plan and legacy-cleanup identities must not come back.
        for retiredFragment in Self.retiredPresenterFragments {
            #expect(!presenter.contains(retiredFragment), Comment(rawValue: retiredFragment))
        }

        for operationMapping in Self.operationMappingFragments {
            #expect(normalizedPresenter.contains(operationMapping))
        }

        for expectation in Self.appMappingExpectations {
            #expect(
                normalizedPresenter.contains(
                    "case \(expectation.identityCase) = \"\(expectation.code)\""
                )
            )
            #expect(
                normalizedPresenter.contains(
                    "func \(expectation.presenterMethod)() -> SafetyNoticeState { "
                        + "notice(for: .\(expectation.identityCase)) }"
                )
            )

            guard let callerPath = expectation.callerPath else {
                continue
            }
            let caller = try Self.readRepositoryFile(callerPath)
            #expect(caller.contains("safetyNoticePresenter.\(expectation.presenterMethod)()"))
            #expect(!caller.contains("selectedStorageReviewNotice(code:"))
        }
    }

    @Test
    func typedSafetyNoticeSemanticsReachEveryStorageToast() throws {
        let toast = try Self.readRepositoryFile(
            "MyMacCleaner/Core/Design/ToastView.swift"
        )
        let normalizedToast = Self.normalizedWhitespace(toast)

        for semanticFragment in [
            "let safetyNotice: SafetyNoticeState?",
            "if let notice = safetyNotice",
            "Text(notice.title)",
            "Text(notice.message)",
            "Button(notice.actionTitle, action: onLearnWhy)",
            ".accessibilityIdentifier(notice.accessibilityIdentifier)",
            "safetyNotice: toast.safetyNotice"
        ] {
            #expect(normalizedToast.contains(semanticFragment), Comment(rawValue: semanticFragment))
        }
        // "Learn why" is a real button, so no hint promises an action that is not there.
        #expect(!toast.contains(".accessibilityHint(notice.actionTitle)"))

        let presenter = try Self.readRepositoryFile(
            "MyMacCleaner/Core/Design/ToastPresenter.swift"
        )
        let normalizedPresenter = Self.normalizedWhitespace(presenter)

        for presenterFragment in [
            "func show(_ message: String, type: ToastType) { "
                + "present(Toast(message: message, type: type, safetyNotice: nil)) }",
            "func show(_ notice: SafetyNoticeState) { "
                + "present(Toast(message: notice.message, type: .info, safetyNotice: notice)) }",
            // A safety notice never times out.
            "guard toast.safetyNotice == nil else { return nil }",
            // An older timer never hides a newer toast.
            "guard current?.id == id else { return }"
        ] {
            #expect(normalizedPresenter.contains(presenterFragment), Comment(rawValue: presenterFragment))
        }

        for expectation in Self.storageToastExpectations {
            let view = try Self.readRepositoryFile(expectation.viewPath)
            let normalizedView = Self.normalizedWhitespace(view)
            let viewModel = try Self.readRepositoryFile(expectation.viewModelPath)
            let normalizedViewModel = Self.normalizedWhitespace(viewModel)

            #expect(
                normalizedView.contains("ToastOverlay(presenter: viewModel.toasts"),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains("let toasts = ToastPresenter()"),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "func showToastMessage(_ message: String, type: ToastType) { "
                        + "toasts.show(message, type: type) }"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "private func publishSafetyNotice(_ notice: SafetyNoticeState) { "
                        + "toasts.show(notice) }"
                ),
                Comment(rawValue: expectation.family)
            )
            // No screen keeps its own copy of the toast lifecycle.
            for retiredFragment in ["presentToast", "toastPresentationID", "showToast = true", "latestSafetyNotice"] {
                #expect(
                    !viewModel.contains(retiredFragment),
                    Comment(rawValue: "\(expectation.family) contains \(retiredFragment)")
                )
            }
        }
    }

    @Test
    func readOnlyInventoriesOfferNoSelectionAndRouteToExperience() throws {
        for path in Self.readOnlyInventorySources {
            let source = try Self.readRepositoryFile(path)
            for selectionFragment in Self.selectionFragments {
                #expect(
                    !source.contains(selectionFragment),
                    Comment(rawValue: "\(path) contains \(selectionFragment)")
                )
            }
        }

        for path in Self.experienceHandoffViews {
            let view = try Self.readRepositoryFile(path)
            #expect(
                view.contains("ExperienceHandoffCard(openExperience:"),
                Comment(rawValue: path)
            )
        }

        let duplicatesView = try Self.readRepositoryFile(
            "MyMacCleaner/Features/Duplicates/DuplicatesView.swift"
        )
        #expect(!duplicatesView.contains(".strikethrough("))
    }

    @Test
    func everyCallableStorageNoticeMappingHasLocalizedKeys() throws {
        let catalogData = try Data(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("MyMacCleaner/Resources/Common.xcstrings")
        )
        let catalog = try #require(
            JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        let strings = try #require(catalog["strings"] as? [String: Any])

        let expectedKeys = [
            "safety.notice.action.learnWhy",
            "safety.notice.emptyTrash.title",
            "safety.notice.emptyingTrashIsNotAvailable.message"
        ]

        for key in expectedKeys {
            #expect(strings[key] != nil)
        }
    }

    private static let storageExpectations: [StoragePresentationExpectation] = [
        .init(
            family: "Home selected scan review",
            code: "home.reviewed-plan-cleanup",
            operation: .reviewedPlanCleanup,
            reason: .reviewedPlanCleanupIsDeferred,
            title: "Reviewed cleanup plans are coming later",
            message: "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready."
        ),
        .init(
            family: "Home automatic trash removal",
            code: "home.empty-trash",
            operation: .emptyTrash,
            reason: .emptyingTrashIsNotAvailable,
            title: "Empty Trash is unavailable",
            message: "MyMacCleaner will not empty Trash automatically."
        ),
        .init(
            family: "Disk Cleaner reviewed cleanup",
            code: "disk.reviewed-plan-cleanup",
            operation: .reviewedPlanCleanup,
            reason: .reviewedPlanCleanupIsDeferred,
            title: "Reviewed cleanup plans are coming later",
            message: "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready."
        ),
        .init(
            family: "Disk automatic trash removal",
            code: "disk.empty-trash",
            operation: .emptyTrash,
            reason: .emptyingTrashIsNotAvailable,
            title: "Empty Trash is unavailable",
            message: "MyMacCleaner will not empty Trash automatically."
        ),
        .init(
            family: "Browser Privacy cleanup",
            code: "browser.legacy-cleanup",
            operation: .legacyCleanup,
            reason: .legacyCleanupRequiresReviewedPlan,
            title: "Legacy cleanup is unavailable",
            message: "MyMacCleaner requires a reviewed cleanup plan before changing files."
        ),
        .init(
            family: "Space Lens cleanup",
            code: "space-lens.reviewed-plan-cleanup",
            operation: .reviewedPlanCleanup,
            reason: .reviewedPlanCleanupIsDeferred,
            title: "Reviewed cleanup plans are coming later",
            message: "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready."
        ),
        .init(
            family: "Duplicates cleanup",
            code: "duplicates.reviewed-plan-cleanup",
            operation: .reviewedPlanCleanup,
            reason: .reviewedPlanCleanupIsDeferred,
            title: "Reviewed cleanup plans are coming later",
            message: "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready."
        ),
        .init(
            family: "Orphaned cleanup",
            code: "orphaned.reviewed-plan-cleanup",
            operation: .reviewedPlanCleanup,
            reason: .reviewedPlanCleanupIsDeferred,
            title: "Reviewed cleanup plans are coming later",
            message: "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready."
        )
    ]

    private static let appMappingExpectations: [AppMappingExpectation] = [
        .init(
            identityCase: "homeEmptyTrash",
            code: "home.empty-trash",
            presenterMethod: "homeTrashReviewNotice",
            callerPath: "MyMacCleaner/Features/Home/HomeViewModel.swift"
        ),
        .init(
            identityCase: "diskEmptyTrash",
            code: "disk.empty-trash",
            presenterMethod: "diskTrashReviewNotice",
            callerPath: "MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift"
        )
    ]

    private static let operationMappingFragments = [
        "case .homeEmptyTrash, .diskEmptyTrash: .emptyTrash"
    ]

    private static let retiredPresenterFragments = [
        "reviewed-plan-cleanup",
        "legacy-cleanup",
        "SelectedStorageReviewNotice",
        "browserPrivacyReviewNotice",
        "duplicatesStorageReviewNotice",
        "orphanedStorageReviewNotice"
    ]

    private static let readOnlyInventorySources = [
        "MyMacCleaner/Features/Home/HomeViewModel.swift",
        "MyMacCleaner/Features/Home/Components/ScanResultsCard.swift",
        "MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift",
        "MyMacCleaner/Features/DiskCleaner/DiskCleanerView.swift",
        "MyMacCleaner/Features/DiskCleaner/Components/CleanupCategoryCard.swift",
        "MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift",
        "MyMacCleaner/Features/Duplicates/DuplicatesViewModel.swift",
        "MyMacCleaner/Features/Duplicates/DuplicatesView.swift",
        "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesViewModel.swift",
        "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesView.swift",
        "MyMacCleaner/Core/Models/ScanResult.swift"
    ]

    private static let selectionFragments = [
        "isSelected",
        "isKept",
        "selectAll",
        "deselectAll",
        "reviewSelected",
        "noSelection",
        "selectedForReview"
    ]

    private static let experienceHandoffViews = [
        "MyMacCleaner/Features/Home/Components/ScanResultsCard.swift",
        "MyMacCleaner/Features/DiskCleaner/DiskCleanerView.swift",
        "MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift",
        "MyMacCleaner/Features/Duplicates/DuplicatesView.swift",
        "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesView.swift"
    ]

    private static let storageToastExpectations: [StorageToastExpectation] = [
        .init(
            family: "Home safety notice",
            viewPath: "MyMacCleaner/Features/Home/HomeView.swift",
            viewModelPath: "MyMacCleaner/Features/Home/HomeViewModel.swift"
        ),
        .init(
            family: "Disk Cleaner safety notice",
            viewPath: "MyMacCleaner/Features/DiskCleaner/DiskCleanerView.swift",
            viewModelPath: "MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift"
        )
    ]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func readRepositoryFile(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func normalizedWhitespace(_ source: String) -> String {
        source.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }
}

private struct StorageToastExpectation {
    let family: String
    let viewPath: String
    let viewModelPath: String
}

private struct AppMappingExpectation {
    let identityCase: String
    let code: String
    let presenterMethod: String
    let callerPath: String?

    init(
        identityCase: String,
        code: String,
        presenterMethod: String,
        callerPath: String? = nil
    ) {
        self.identityCase = identityCase
        self.code = code
        self.presenterMethod = presenterMethod
        self.callerPath = callerPath
    }
}

private struct StoragePresentationExpectation {
    let family: String
    let code: String
    let operation: UnsupportedOperation
    let reason: DisabledOperationReason
    let title: String
    let message: String
    let isDestructive: Bool
    let accessibilityID: String
    let payload: Never?

    init(
        family: String,
        code: String,
        operation: UnsupportedOperation,
        reason: DisabledOperationReason,
        title: String,
        message: String,
        isDestructive: Bool = false,
        payload: Never? = nil
    ) {
        self.family = family
        self.code = code
        self.operation = operation
        self.reason = reason
        self.title = title
        self.message = message
        self.isDestructive = isDestructive
        self.accessibilityID = "safety.notice.\(code)"
        self.payload = payload
    }
}
