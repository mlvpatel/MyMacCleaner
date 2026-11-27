import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Duplicates List Tests

@Suite("Duplicates List Tests")
@MainActor
struct DuplicatesListTests {
    private func group(_ paths: [String], size: Int64) -> DuplicateGroup {
        DuplicateGroup(
            hash: UUID().uuidString,
            files: paths.map { DuplicateFile(url: URL(fileURLWithPath: $0), size: size, modificationDate: nil) }
        )
    }

    @Test("The cached list follows new results, the type filter and the sort order at once")
    func listFollowsResultsFilterAndSort() {
        let viewModel = DuplicatesViewModel()
        let photo = group(["/a/Photo.JPG", "/b/Photo.JPG"], size: 100)
        let report = group(["/a/report.pdf", "/b/report.pdf", "/c/report.pdf"], size: 40)

        viewModel.duplicateGroups = [report, photo]
        #expect(viewModel.filteredGroups.map(\.id) == [photo.id, report.id])
        #expect(viewModel.fileTypeStats.map(\.0) == [.image, .document])

        viewModel.sortOrder = .duplicateCountDescending
        #expect(viewModel.filteredGroups.map(\.id) == [report.id, photo.id])

        viewModel.filterType = .image
        #expect(viewModel.filteredGroups.map(\.id) == [photo.id])
    }

    @Test("Search waits for typing to pause, then matches any copy's path case-insensitively")
    func searchIsDebounced() async {
        let viewModel = DuplicatesViewModel()
        let photo = group(["/a/Photo.JPG", "/b/Photo.JPG"], size: 100)
        let report = group(["/a/report.pdf", "/c/report.pdf"], size: 40)
        viewModel.duplicateGroups = [photo, report]

        viewModel.searchText = "PHOTO"
        #expect(viewModel.filteredGroups.count == 2)
        await viewModel.searchTask?.value
        #expect(viewModel.filteredGroups.map(\.id) == [photo.id])

        viewModel.searchText = "/C/"
        await viewModel.searchTask?.value
        #expect(viewModel.filteredGroups.map(\.id) == [report.id])

        viewModel.clearFilter()
        await viewModel.searchTask?.value
        #expect(viewModel.filteredGroups.count == 2)
    }

    @Test("A search that hides every group is reported, and clearing it brings the list back")
    func searchWithoutMatchesIsReported() async {
        let viewModel = DuplicatesViewModel()
        #expect(viewModel.hasNoSearchMatches == false)
        viewModel.duplicateGroups = [group(["/a/Photo.JPG", "/b/Photo.JPG"], size: 100)]
        #expect(viewModel.hasNoSearchMatches == false)

        viewModel.searchText = "invoice"
        await viewModel.searchTask?.value
        #expect(viewModel.hasNoSearchMatches)

        viewModel.clearFilter()
        #expect(viewModel.hasNoSearchMatches == false)
    }

    @Test("Choosing another folder after a scan clears the old folder's results; the same folder keeps them")
    func newFolderClearsResults() async {
        let photo = group(["/a/Photo.JPG", "/b/Photo.JPG"], size: 100)
        let viewModel = DuplicatesViewModel(scan: { _, _ in
            DuplicateScanResult(groups: [photo], isTruncated: true, skippedCloudOnlyCount: 2)
        })
        viewModel.startScan()
        await viewModel.scanTask?.value
        #expect(viewModel.hasScanned)

        viewModel.scanPath = viewModel.scanPath
        #expect(viewModel.hasScanned)
        #expect(viewModel.duplicateGroups.map(\.id) == [photo.id])

        viewModel.scanPath = URL(fileURLWithPath: "/Volumes/Other/Folder")
        #expect(viewModel.hasScanned == false)
        #expect(viewModel.duplicateGroups.isEmpty)
        #expect(viewModel.isTruncated == false)
        #expect(viewModel.skippedCloudOnlyCount == 0)
    }
}

// MARK: - Orphaned Files List Tests

@Suite("Orphaned Files List Tests")
@MainActor
struct OrphanedFilesListTests {
    private let library = "/Users/test/Library"

    private func orphan(_ path: String, app: String, bundle: String?, size: Int64) -> OrphanedFile {
        let url = URL(fileURLWithPath: library + path)
        return OrphanedFile(
            url: url,
            name: url.lastPathComponent,
            suspectedAppName: app,
            bundleIdPattern: bundle,
            size: size,
            modificationDate: nil
        )
    }

    @Test("Files are grouped by category once, in category order, and follow the sort order")
    func groupsFollowResultsAndSort() {
        let viewModel = OrphanedFilesViewModel()
        let oldCache = orphan("/Caches/com.old.App", app: "Old App", bundle: "com.old.app", size: 300)
        let toolPrefs = orphan("/Preferences/com.gone.Tool.plist", app: "Gone Tool", bundle: nil, size: 20)
        let toolCache = orphan("/Caches/com.gone.Tool", app: "Gone Tool", bundle: "com.gone.tool", size: 500)

        viewModel.orphanedFiles = [oldCache, toolPrefs, toolCache]
        #expect(viewModel.categoriesWithFiles == [.preferences, .caches])
        #expect(viewModel.filesByCategory[.caches]?.map(\.id) == [toolCache.id, oldCache.id])

        viewModel.sortOrder = .sizeAscending
        #expect(viewModel.filesByCategory[.caches]?.map(\.id) == [oldCache.id, toolCache.id])
    }

    @Test("Search waits for typing to pause and matches name, app or bundle ID case-insensitively")
    func searchIsDebounced() async {
        let viewModel = OrphanedFilesViewModel()
        let oldCache = orphan("/Caches/com.old.App", app: "Old App", bundle: "com.old.app", size: 300)
        let toolPrefs = orphan("/Preferences/com.gone.Tool.plist", app: "Gone Tool", bundle: nil, size: 20)
        viewModel.orphanedFiles = [oldCache, toolPrefs]

        viewModel.searchText = "gone TOOL"
        #expect(viewModel.categoriesWithFiles == [.preferences, .caches])
        await viewModel.searchTask?.value
        #expect(viewModel.categoriesWithFiles == [.preferences])

        viewModel.searchText = "COM.OLD"
        await viewModel.searchTask?.value
        #expect(viewModel.filesByCategory[.caches]?.map(\.id) == [oldCache.id])
        #expect(viewModel.filesByCategory[.preferences] == nil)
    }

    @Test("A search that hides every file is reported, and clearing it brings the list back")
    func searchWithoutMatchesIsReported() async {
        let viewModel = OrphanedFilesViewModel()
        #expect(viewModel.hasNoSearchMatches == false)
        viewModel.orphanedFiles = [orphan("/Caches/com.old.App", app: "Old App", bundle: "com.old.app", size: 300)]
        #expect(viewModel.hasNoSearchMatches == false)

        viewModel.searchText = "invoice"
        await viewModel.searchTask?.value
        #expect(viewModel.hasNoSearchMatches)

        viewModel.clearSearch()
        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.hasNoSearchMatches == false)
    }
}
