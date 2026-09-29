import SwiftUI

// MARK: - Space Lens View Model

// MARK: - Filter Enums

enum SizeFilter: String, CaseIterable {
    case all = "All"
    case over100MB = ">100 MB"
    case over500MB = ">500 MB"
    case over1GB = ">1 GB"

    var localizedName: String {
        switch self {
        case .all: return L("spaceLens.filter.size.all")
        case .over100MB: return L("spaceLens.filter.size.over100MB")
        case .over500MB: return L("spaceLens.filter.size.over500MB")
        case .over1GB: return L("spaceLens.filter.size.over1GB")
        }
    }

    var minSize: Int64 {
        switch self {
        case .all: return 0
        case .over100MB: return 100 * 1024 * 1024
        case .over500MB: return 500 * 1024 * 1024
        case .over1GB: return 1024 * 1024 * 1024
        }
    }
}

enum AgeFilter: String, CaseIterable {
    case all = "All"
    case over30Days = ">30 days"
    case over90Days = ">90 days"
    case over1Year = ">1 year"

    var localizedName: String {
        switch self {
        case .all: return L("spaceLens.filter.age.all")
        case .over30Days: return L("spaceLens.filter.age.over30Days")
        case .over90Days: return L("spaceLens.filter.age.over90Days")
        case .over1Year: return L("spaceLens.filter.age.over1Year")
        }
    }

    var minAge: TimeInterval {
        switch self {
        case .all: return 0
        case .over30Days: return 30 * 24 * 60 * 60
        case .over90Days: return 90 * 24 * 60 * 60
        case .over1Year: return 365 * 24 * 60 * 60
        }
    }
}

@MainActor
class SpaceLensViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var currentPath: String = ""

    @Published var rootNode: FileNode?
    @Published var currentNode: FileNode?
    @Published var navigationStack: [FileNode] = []

    @Published var selectedNode: FileNode?
    @Published var hoveredNode: FileNode?

    @Published var errorMessage: String?

    /// True when the last scan stopped at `SpaceLensScanLimits.maxEntries`.
    @Published private(set) var isTruncated = false

    /// Readable so tests can await a cancelled scan instead of sleeping.
    private(set) var scanTask: Task<Void, Never>?

    // Filters
    @Published var sizeFilter: SizeFilter = .all
    @Published var ageFilter: AgeFilter = .all

    // MARK: - Computed Properties

    var breadcrumbs: [FileNode] {
        navigationStack
    }

    var currentChildren: [FileNode] {
        filteredChildren(of: currentNode)
    }

    var formattedCurrentSize: String {
        guard let node = currentNode else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file)
    }

    var hasActiveFilters: Bool {
        sizeFilter != .all || ageFilter != .all
    }

    var filteredCount: Int {
        currentChildren.count
    }

    var totalCount: Int {
        currentNode?.children.count ?? 0
    }

    // MARK: - Filter Methods

    private func filteredChildren(of node: FileNode?) -> [FileNode] {
        guard let node = node else { return [] }

        return node.children.filter { child in
            // Size filter
            if sizeFilter != .all && child.size < sizeFilter.minSize {
                return false
            }

            // Age filter (only applies to files, not directories)
            if ageFilter != .all && !child.isDirectory {
                if let accessDate = child.lastAccessDate {
                    let age = Date().timeIntervalSince(accessDate)
                    if age < ageFilter.minAge {
                        return false
                    }
                }
            }

            return true
        }
    }

    func clearFilters() {
        sizeFilter = .all
        ageFilter = .all
    }

    // MARK: - Public Methods

    func scanDirectory(_ url: URL) {
        guard !isScanning else { return }

        isScanning = true
        isTruncated = false
        scanProgress = 0
        errorMessage = nil

        scanTask = Task { [weak self] in
            do {
                let result = try await Self.buildFileTree(
                    url: url,
                    maxEntries: SpaceLensScanLimits.maxEntries
                ) { progress, path in
                    guard let self, self.isScanning else { return }
                    self.scanProgress = progress
                    self.currentPath = path
                }
                guard !Task.isCancelled, let self else { return }
                self.rootNode = result.root
                self.currentNode = result.root
                self.navigationStack = [result.root]
                self.isTruncated = result.isTruncated
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = LFormat("spaceLens.scanFailed %@", error.localizedDescription)
            }
            self?.finishScan()
        }
    }

    /// Stops an in-flight scan, keeping any previously completed tree.
    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        finishScan()
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
        currentPath = ""
    }

    func scanHomeDirectory() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        scanDirectory(homeURL)
    }

    func navigateTo(_ node: FileNode) {
        guard node.isDirectory else { return }

        withAnimation(Theme.Animation.spring) {
            currentNode = node
            if let index = navigationStack.firstIndex(where: { $0.id == node.id }) {
                navigationStack = Array(navigationStack.prefix(through: index))
            } else {
                navigationStack.append(node)
            }
        }
    }

    func navigateUp() {
        guard navigationStack.count > 1 else { return }

        withAnimation(Theme.Animation.spring) {
            navigationStack.removeLast()
            currentNode = navigationStack.last
        }
    }

    func hoverNode(_ node: FileNode?) {
        hoveredNode = node
    }

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.selectFile(node.url.path, inFileViewerRootedAtPath: node.url.deletingLastPathComponent().path)
    }

    // MARK: - Tree Building

    /// Walks `url` off the main actor. Checks cancellation between entries and stops
    /// collecting after `maxEntries` so very large homes cannot exhaust memory.
    nonisolated static func buildFileTree(
        url: URL,
        maxEntries: Int,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> SpaceLensScanResult {
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isDirectoryKey,
            .nameKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            let empty = FileNode(name: url.lastPathComponent, url: url, size: 0, isDirectory: true, children: [])
            return SpaceLensScanResult(root: empty, isTruncated: false)
        }

        // Phase 1: Enumerate files (0-85%)
        var fileCount = 0
        var isTruncated = false
        var directoryContents: [URL: [FileNode]] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            if fileCount >= maxEntries {
                isTruncated = true
                break
            }
            fileCount += 1

            if fileCount % SpaceLensScanLimits.progressInterval == 0 {
                try Task.checkCancellation()
                let fraction = Double(fileCount) / Double(SpaceLensScanLimits.progressEstimateEntries)
                await progress(min(0.85, fraction * 0.85), fileURL.lastPathComponent)
            }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            let childNode = FileNode(
                name: resourceValues.name ?? fileURL.lastPathComponent,
                url: fileURL,
                size: Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0),
                isDirectory: resourceValues.isDirectory ?? false,
                lastAccessDate: resourceValues.contentAccessDate,
                modificationDate: resourceValues.contentModificationDate,
                children: []
            )
            directoryContents[fileURL.deletingLastPathComponent(), default: []].append(childNode)
        }

        try Task.checkCancellation()

        // Phase 2: Building tree structure (85-100%)
        await progress(0.90, L("spaceLens.scan.buildingTree"))
        let root = buildTreeFromContents(root: url, contents: directoryContents)
        await progress(1.0, L("common.complete"))

        return SpaceLensScanResult(root: root, isTruncated: isTruncated)
    }

    private nonisolated static func buildTreeFromContents(root: URL, contents: [URL: [FileNode]]) -> FileNode {
        func buildNode(url: URL) -> FileNode {
            let children = contents[url] ?? []
            var builtChildren: [FileNode] = []
            var totalSize: Int64 = 0

            for child in children {
                if child.isDirectory {
                    let builtChild = buildNode(url: child.url)
                    builtChildren.append(builtChild)
                    totalSize += builtChild.size
                } else {
                    builtChildren.append(child)
                    totalSize += child.size
                }
            }

            // Sort by size descending
            builtChildren.sort { $0.size > $1.size }

            return FileNode(
                name: url.lastPathComponent,
                url: url,
                size: totalSize,
                isDirectory: true,
                children: builtChildren
            )
        }

        // The enumerator reports resolved paths (e.g. /private/var for /var), so a root reached
        // through a symlink has no exact key. Every key is the root or below it, so the
        // shallowest key is the root.
        let rootKey = contents[root] != nil
            ? root
            : contents.keys.min { $0.pathComponents.count < $1.pathComponents.count } ?? root
        let built = buildNode(url: rootKey)
        return FileNode(
            name: root.lastPathComponent,
            url: root,
            size: built.size,
            isDirectory: true,
            children: built.children
        )
    }
}

// MARK: - Scan Result

enum SpaceLensScanLimits {
    /// Upper bound on collected entries; beyond this the tree is marked truncated.
    static let maxEntries = 500_000
    /// Entries between cancellation checks and progress updates.
    static let progressInterval = 200
    /// Entry count used to scale the enumeration progress bar.
    static let progressEstimateEntries = 50_000
}

struct SpaceLensScanResult {
    let root: FileNode
    let isTruncated: Bool
}

// MARK: - File Node

class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let url: URL
    @Published var size: Int64
    let isDirectory: Bool
    let lastAccessDate: Date?
    let modificationDate: Date?
    @Published var children: [FileNode]

    init(name: String, url: URL, size: Int64, isDirectory: Bool, lastAccessDate: Date? = nil, modificationDate: Date? = nil, children: [FileNode]) {
        self.name = name
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
        self.lastAccessDate = lastAccessDate
        self.modificationDate = modificationDate
        self.children = children
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedLastAccess: String? {
        guard let date = lastAccessDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var daysSinceAccess: Int? {
        guard let date = lastAccessDate else { return nil }
        let interval = Date().timeIntervalSince(date)
        return Int(interval / (24 * 60 * 60))
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var color: Color {
        if isDirectory {
            return .blue
        }

        switch fileExtension {
        case "app": return .purple
        case "dmg", "pkg", "zip", "gz", "tar": return .orange
        case "mp4", "mov", "avi", "mkv": return .pink
        case "mp3", "wav", "aac", "m4a": return .green
        case "jpg", "jpeg", "png", "gif", "heic": return .cyan
        case "pdf": return .red
        case "doc", "docx", "txt", "rtf": return .blue
        case "xls", "xlsx", "csv": return .green
        case "ppt", "pptx": return .orange
        default: return .gray
        }
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }

        switch fileExtension {
        case "app": return "app"
        case "dmg": return "externaldrive"
        case "pkg": return "shippingbox"
        case "zip", "gz", "tar": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "m4a": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "doc", "docx", "txt", "rtf": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "play.rectangle"
        default: return "doc"
        }
    }
}
