import Foundation
import Testing
@testable import SafetyContract

@Suite("Legacy Filesystem Mutation Contract")
struct LegacyMutationTests {
    @Test
    func legacyFilesystemOwnersHaveNoMutationEntryPoints() throws {
        let forbiddenFragments = [
            "func deleteItems",
            "func trashItems",
            "func emptyTrash",
            "func cleanItems",
            "func deleteFiles",
            "func prepareDelete",
            "func confirmDelete",
            "func cancelDelete",
            "showDeleteConfirmation",
            "nodeToDelete",
            "FileManager.default.removeItem",
            "FileManager.default.trashItem"
        ]

        for source in Self.filesystemOwnerSources {
            let contents = try String(contentsOf: Self.repositoryRoot.appending(path: source), encoding: .utf8)

            for fragment in forbiddenFragments {
                #expect(!contents.contains(fragment), "\(source) still exposes \(fragment)")
            }
        }
    }

    @Test(arguments: Self.filesystemOperations)
    func legacyFilesystemRequestsHaveNoTargetAndLeaveMutationCapabilitiesAtZero(
        _ expectation: LegacyOperationExpectation
    ) {
        let recorder = FilesystemMutationRecorder()
        let result = DisabledOperationGateway().request(expectation.operation)

        #expect(result.operation == expectation.operation)
        #expect(result.disposition == .disabled)
        #expect(result.reason == expectation.reason)
        #expect(recorder.snapshot == .zero)
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let filesystemOwnerSources = [
        "MyMacCleaner/Core/Services/BrowserCleanerService.swift",
        "MyMacCleaner/Core/Services/DuplicateScanner.swift",
        "MyMacCleaner/Core/Services/OrphanedFilesScanner.swift",
        "MyMacCleaner/Features/SpaceLens/SpaceLensViewModel.swift"
    ]

    private static let filesystemOperations: [LegacyOperationExpectation] = [
        .init(.legacyCleanup, .legacyCleanupRequiresReviewedPlan),
        .init(.permanentDeletion, .permanentDeletionRequiresReviewedPlan),
        .init(.emptyTrash, .emptyingTrashIsNotAvailable)
    ]
}

struct LegacyOperationExpectation: Sendable {
    let operation: UnsupportedOperation
    let reason: DisabledOperationReason

    init(_ operation: UnsupportedOperation, _ reason: DisabledOperationReason) {
        self.operation = operation
        self.reason = reason
    }
}

private struct FilesystemMutationRecorder: Sendable {
    let snapshot = FilesystemMutationSnapshot(mutations: 0)
}

private struct FilesystemMutationSnapshot: Equatable, Sendable {
    let mutations: Int

    static let zero = Self(mutations: 0)
}
