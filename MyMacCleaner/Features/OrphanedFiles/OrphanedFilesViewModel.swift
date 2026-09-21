import SwiftUI

@MainActor
class OrphanedFilesViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var scanProgress: Double = 0
    @Published var currentScanCategory: String = ""

    @Published var orphanedFiles: [OrphanedFile] = []

    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastType: ToastType = .success
    @Published private(set) var latestSafetyNotice: SafetyNoticeState?

    @Published var expandedCategory: OrphanCategory?
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .sizeDescending

    // MARK: - Enums

    enum SortOrder: String, CaseIterable {
        case sizeDescending = "Size (Largest)"
        case sizeAscending = "Size (Smallest)"
        case dateDescending = "Date (Newest)"
        case dateAscending = "Date (Oldest)"
        case nameAscending = "Name (A-Z)"

        var localizedName: String {
            switch self {
            case .sizeDescending: return L("orphans.sort.sizeLargest")
            case .sizeAscending: return L("orphans.sort.sizeSmallest")
            case .dateDescending: return L("orphans.sort.dateNewest")
            case .dateAscending: return L("orphans.sort.dateOldest")
            case .nameAscending: return L("orphans.sort.name")
            }
        }
    }

    // MARK: - Computed Properties

    var filteredFiles: [OrphanedFile] {
        var result = orphanedFiles

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.suspectedAppName.lowercased().contains(query) ||
                ($0.bundleIdPattern?.lowercased().contains(query) ?? false)
            }
        }

        // Apply sort
        switch sortOrder {
        case .sizeDescending:
            result.sort { $0.size > $1.size }
        case .sizeAscending:
            result.sort { $0.size < $1.size }
        case .dateDescending:
            result.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .dateAscending:
            result.sort { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        case .nameAscending:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return result
    }

    var filesByCategory: [OrphanCategory: [OrphanedFile]] {
        Dictionary(grouping: filteredFiles, by: { $0.category })
    }

    var totalSize: Int64 {
        orphanedFiles.reduce(0) { $0 + $1.size }
    }

    var selectedSize: Int64 {
        orphanedFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        orphanedFiles.filter { $0.isSelected }.count
    }

    var totalCount: Int {
        orphanedFiles.count
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }

    var categoriesWithFiles: [OrphanCategory] {
        OrphanCategory.allCases.filter { category in
            filesByCategory[category]?.isEmpty == false
        }
    }

    // MARK: - Scanner

    private let scanner = OrphanedFilesScanner.shared
    private let safetyNoticePresenter = SafetyNoticePresenter()
    private var toastPresentationID = UUID()
    /// Readable so tests can await a cancelled scan instead of sleeping.
    private(set) var scanTask: Task<Void, Never>?

    // MARK: - Actions

    func startScan() {
        guard !isScanning else { return }

        isScanning = true
        hasScanned = false
        scanProgress = 0
        orphanedFiles = []

        scanTask = Task { [scanner] in
            let results = await scanner.scan { progress, category in
                Task { @MainActor in
                    guard self.isScanning else { return }
                    self.scanProgress = progress
                    self.currentScanCategory = category
                }
            }
            guard !Task.isCancelled else { return }

            orphanedFiles = results
            hasScanned = true
            finishScan()
        }
    }

    /// Stops an in-flight scan; nothing is reported as scanned.
    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        finishScan()
        scanProgress = 0
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
    }

    func toggleSelection(_ file: OrphanedFile) {
        if let index = orphanedFiles.firstIndex(where: { $0.id == file.id }) {
            orphanedFiles[index].isSelected.toggle()
        }
    }

    func toggleCategorySelection(_ category: OrphanCategory) {
        let categoryFiles = orphanedFiles.filter { $0.category == category }
        let allSelected = categoryFiles.allSatisfy { $0.isSelected }

        // Create a mutable copy to ensure @Published triggers properly
        var updatedFiles = orphanedFiles
        for i in updatedFiles.indices {
            if updatedFiles[i].category == category {
                updatedFiles[i].isSelected = !allSelected
            }
        }
        orphanedFiles = updatedFiles
    }

    func selectAll() {
        // Create a mutable copy to ensure @Published triggers properly and avoid mutation during iteration
        var updatedFiles = orphanedFiles
        for i in updatedFiles.indices {
            updatedFiles[i].isSelected = true
        }
        orphanedFiles = updatedFiles
    }

    func deselectAll() {
        // Create a mutable copy to ensure @Published triggers properly and avoid mutation during iteration
        var updatedFiles = orphanedFiles
        for i in updatedFiles.indices {
            updatedFiles[i].isSelected = false
        }
        orphanedFiles = updatedFiles
    }

    func toggleCategoryExpansion(_ category: OrphanCategory) {
        withAnimation(Theme.Animation.spring) {
            if expandedCategory == category {
                expandedCategory = nil
            } else {
                expandedCategory = category
            }
        }
    }

    func explainOrphanReview() {
        guard selectedCount > 0 else {
            showToastMessage(L("safety.notice.noSelection"), type: .info)
            return
        }

        publishSafetyNotice(
            safetyNoticePresenter.orphanedStorageReviewNotice()
        )
    }

    func revealInFinder(_ file: OrphanedFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
    }

    func dismissToast() {
        showToast = false
        latestSafetyNotice = nil
    }

    private func publishSafetyNotice(_ notice: SafetyNoticeState) {
        latestSafetyNotice = notice
        presentToast(notice.message, type: .info)
    }

    private func showToastMessage(_ message: String, type: ToastType) {
        latestSafetyNotice = nil
        presentToast(message, type: type)
    }

    private func presentToast(_ message: String, type: ToastType) {
        let presentationID = UUID()
        toastPresentationID = presentationID
        toastMessage = message
        toastType = type
        showToast = true

        Task {
            try? await Task.sleep(for: .seconds(3))
            guard toastPresentationID == presentationID else { return }
            dismissToast()
        }
    }
}
