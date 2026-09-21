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
            "Text(notice.actionTitle)",
            ".accessibilityIdentifier(notice.accessibilityIdentifier)",
            ".accessibilityHint(notice.actionTitle)"
        ] {
            #expect(normalizedToast.contains(semanticFragment))
        }

        for expectation in Self.storageToastExpectations {
            let view = try Self.readRepositoryFile(expectation.viewPath)
            let normalizedView = Self.normalizedWhitespace(view)
            let viewModel = try Self.readRepositoryFile(expectation.viewModelPath)
            let normalizedViewModel = Self.normalizedWhitespace(viewModel)

            #expect(
                normalizedView.contains(
                    "safetyNotice: viewModel.latestSafetyNotice"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "showToastMessage(_ message: String, type: ToastType) { "
                        + "latestSafetyNotice = nil presentToast(message, type: type) }"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "private func publishSafetyNotice(_ notice: SafetyNoticeState) { "
                        + "latestSafetyNotice = notice presentToast(notice.message, type: .info) }"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "func dismissToast() { showToast = false latestSafetyNotice = nil }"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "let presentationID = UUID() toastPresentationID = presentationID"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                normalizedViewModel.contains(
                    "guard toastPresentationID == presentationID else { return } "
                        + "dismissToast()"
                ),
                Comment(rawValue: expectation.family)
            )
            #expect(
                Self.occurrenceCount(of: "showToast = true", in: viewModel) == 1,
                Comment(rawValue: expectation.family)
            )
            #expect(
                Self.occurrenceCount(of: "showToast = false", in: viewModel) == 2,
                Comment(rawValue: expectation.family)
            )
        }
    }

    @Test
    func duplicateReviewSelectionDoesNotLookDeleted() throws {
        let duplicatesView = try Self.readRepositoryFile(
            "MyMacCleaner/Features/Duplicates/DuplicatesView.swift"
        )

        #expect(!duplicatesView.contains(".strikethrough(file.isSelected"))
        #expect(!duplicatesView.contains(".opacity(file.isSelected && !file.isKept"))
        #expect(duplicatesView.contains("Text(L(\"safety.notice.selectedForReview\"))"))
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
            "safety.notice.emptyingTrashIsNotAvailable.message",
            "safety.notice.legacyCleanup.title",
            "safety.notice.legacyCleanupRequiresReviewedPlan.message",
            "safety.notice.reviewedPlanCleanup.title",
            "safety.notice.reviewedPlanCleanupIsDeferred.message"
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
            identityCase: "homeReviewedPlanCleanup",
            code: "home.reviewed-plan-cleanup",
            presenterMethod: "homeSelectedStorageReviewNotice",
            callerPath: "MyMacCleaner/Features/Home/HomeViewModel.swift"
        ),
        .init(
            identityCase: "homeEmptyTrash",
            code: "home.empty-trash",
            presenterMethod: "homeTrashReviewNotice",
            callerPath: "MyMacCleaner/Features/Home/HomeViewModel.swift"
        ),
        .init(
            identityCase: "diskReviewedPlanCleanup",
            code: "disk.reviewed-plan-cleanup",
            presenterMethod: "diskSelectedStorageReviewNotice",
            callerPath: "MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift"
        ),
        .init(
            identityCase: "diskEmptyTrash",
            code: "disk.empty-trash",
            presenterMethod: "diskTrashReviewNotice",
            callerPath: "MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift"
        ),
        .init(
            identityCase: "browserLegacyCleanup",
            code: "browser.legacy-cleanup",
            presenterMethod: "browserPrivacyReviewNotice",
            callerPath: "MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift"
        ),
        .init(
            identityCase: "duplicatesReviewedPlanCleanup",
            code: "duplicates.reviewed-plan-cleanup",
            presenterMethod: "duplicatesStorageReviewNotice",
            callerPath: "MyMacCleaner/Features/Duplicates/DuplicatesViewModel.swift"
        ),
        .init(
            identityCase: "orphanedReviewedPlanCleanup",
            code: "orphaned.reviewed-plan-cleanup",
            presenterMethod: "orphanedStorageReviewNotice",
            callerPath: "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesViewModel.swift"
        )
    ]

    private static let operationMappingFragments = [
        "case .homeReviewedPlanCleanup, .diskReviewedPlanCleanup, "
            + ".duplicatesReviewedPlanCleanup, .orphanedReviewedPlanCleanup: "
            + ".reviewedPlanCleanup",
        "case .homeEmptyTrash, .diskEmptyTrash: .emptyTrash",
        "case .browserLegacyCleanup: .legacyCleanup"
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
        ),
        .init(
            family: "Browser Privacy safety notice",
            viewPath: "MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift",
            viewModelPath: "MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift"
        ),
        .init(
            family: "Duplicates safety notice",
            viewPath: "MyMacCleaner/Features/Duplicates/DuplicatesView.swift",
            viewModelPath: "MyMacCleaner/Features/Duplicates/DuplicatesViewModel.swift"
        ),
        .init(
            family: "Orphaned Files safety notice",
            viewPath: "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesView.swift",
            viewModelPath: "MyMacCleaner/Features/OrphanedFiles/OrphanedFilesViewModel.swift"
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

    private static func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
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
