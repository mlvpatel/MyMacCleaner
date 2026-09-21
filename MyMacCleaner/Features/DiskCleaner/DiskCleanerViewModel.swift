import SwiftUI

@MainActor
class DiskCleanerViewModel: ObservableObject {
    // MARK: - Published Properties

    // Scanning state
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var currentScanCategory: ScanCategory?

    // Results
    @Published var scanResults: [ScanResult] = []
    @Published var hasScanned = false

    // Selection
    @Published var expandedCategory: ScanCategory?
    @Published var selectedCategory: ScanResult?
    @Published var showCategoryDetail = false

    // Toast
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastType: ToastType = .success
    @Published private(set) var latestSafetyNotice: SafetyNoticeState?

    // Trash inventory (read-only)
    @Published private(set) var trashInventory: TrashInventory = .unknown

    // Errors
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    var totalReviewableSize: Int64 {
        scanResults.reduce(0) { $0 + $1.totalSize }
    }

    var selectedSize: Int64 {
        scanResults.reduce(0) { $0 + $1.selectedSize }
    }

    var totalItemCount: Int {
        scanResults.reduce(0) { $0 + $1.itemCount }
    }

    var selectedItemCount: Int {
        scanResults.reduce(0) { result, scanResult in
            result + scanResult.items.filter { $0.isSelected }.count
        }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalReviewableSize, countStyle: .file)
    }

    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }


    var hasFullDiskAccess: Bool {
        permissionsService.hasFullDiskAccess
    }

    // MARK: - Private Properties

    private let liveScan: CleanerCoreLiveScan
    private let permissionsService = PermissionsService.shared
    private let safetyNoticePresenter = SafetyNoticePresenter()
    private var toastPresentationID = UUID()
    private var scanTask: Task<Void, Never>?
    private var trashTask: Task<Void, Never>?

    // MARK: - Initialization

    init(scan: CleanerCoreLiveScan = CleanerCoreLiveScan()) {
        liveScan = scan
    }

    // MARK: - Public Methods

    func startScan() {
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        scanResults = []
        errorMessage = nil

        scanTask = Task { [liveScan] in
            do {
                let results = try await liveScan.scanAllCategories { progress, category in
                    guard self.isScanning else { return }
                    self.scanProgress = progress
                    self.currentScanCategory = category
                }
                // A cancelled scan returns partial evidence; never present it as a result.
                guard !Task.isCancelled else { return }

                scanResults = results
                hasScanned = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = LFormat("diskCleaner.toast.scanFailed %@", error.localizedDescription)
            }

            finishScan()
        }
    }

    /// Stops an in-flight scan and discards its partial results.
    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        finishScan()
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
        currentScanCategory = nil
    }

    func toggleCategoryExpansion(_ category: ScanCategory) {
        withAnimation(Theme.Animation.spring) {
            if expandedCategory == category {
                expandedCategory = nil
            } else {
                expandedCategory = category
            }
        }
    }

    func showDetails(for result: ScanResult) {
        selectedCategory = result
        showCategoryDetail = true
    }

    func toggleItemSelection(_ item: CleanableItem, in category: ScanCategory) {
        guard let resultIndex = scanResults.firstIndex(where: { $0.category == category }),
              let itemIndex = scanResults[resultIndex].items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        scanResults[resultIndex].items[itemIndex].isSelected.toggle()
    }

    func toggleCategorySelection(_ category: ScanCategory) {
        guard let resultIndex = scanResults.firstIndex(where: { $0.category == category }) else {
            return
        }

        let allSelected = scanResults[resultIndex].items.allSatisfy { $0.isSelected }

        // Create a mutable copy to ensure @Published triggers properly
        var updatedResults = scanResults
        for i in updatedResults[resultIndex].items.indices {
            updatedResults[resultIndex].items[i].isSelected = !allSelected
        }
        scanResults = updatedResults
    }

    func selectAll() {
        // Create a mutable copy to ensure @Published triggers properly and avoid mutation during iteration
        var updatedResults = scanResults
        for resultIndex in updatedResults.indices {
            for itemIndex in updatedResults[resultIndex].items.indices {
                updatedResults[resultIndex].items[itemIndex].isSelected = true
            }
        }
        scanResults = updatedResults
    }

    func deselectAll() {
        // Create a mutable copy to ensure @Published triggers properly and avoid mutation during iteration
        var updatedResults = scanResults
        for resultIndex in updatedResults.indices {
            for itemIndex in updatedResults[resultIndex].items.indices {
                updatedResults[resultIndex].items[itemIndex].isSelected = false
            }
        }
        scanResults = updatedResults
    }

    func explainSelectedStorageReview() {
        guard selectedItemCount > 0 else {
            showToastMessage(L("safety.notice.noSelection"), type: .info)
            return
        }

        publishSafetyNotice(
            safetyNoticePresenter.diskSelectedStorageReviewNotice()
        )
    }

    func showToastMessage(_ message: String, type: ToastType) {
        latestSafetyNotice = nil
        presentToast(message, type: type)
    }

    func dismissToast() {
        showToast = false
        latestSafetyNotice = nil
    }

    // MARK: - Trash Inventory

    /// Re-measures the Trash off the main actor; a newer request supersedes an older one.
    func refreshTrashSize() {
        trashTask?.cancel()
        trashTask = Task {
            let inventory = await TrashInventoryReader.measure()
            guard !Task.isCancelled else { return }
            trashInventory = inventory
            trashTask = nil
        }
    }

    func explainTrashSafety() {
        publishSafetyNotice(safetyNoticePresenter.diskTrashReviewNotice())
    }

    // MARK: - Helpers

    func result(for category: ScanCategory) -> ScanResult? {
        scanResults.first { $0.category == category }
    }

    private func publishSafetyNotice(_ notice: SafetyNoticeState) {
        latestSafetyNotice = notice
        presentToast(notice.message, type: .info)
    }

    private func presentToast(_ message: String, type: ToastType) {
        let presentationID = UUID()
        toastPresentationID = presentationID
        toastMessage = message
        toastType = type
        showToast = true

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard toastPresentationID == presentationID else { return }
            dismissToast()
        }
    }
}
