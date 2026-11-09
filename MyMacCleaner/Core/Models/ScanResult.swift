import Foundation
import SwiftUI

// MARK: - Scan Result

struct ScanResult: Identifiable {
    let id = UUID()
    let category: ScanCategory
    var items: [CleanableItem]

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var itemCount: Int {
        items.count
    }
}

// MARK: - Scan Category

/// One category per general-Mac scan root (1:1 with `GeneralMacRootKind`), so a finding is
/// labelled by the folder it came from and personal folders are never called junk.
enum ScanCategory: String, CaseIterable, Identifiable {
    case caches
    case logs
    case temporaryFiles
    case downloads
    case desktop
    case documents

    var id: String { rawValue }

    /// The user's own folders: listed for review only and never counted as app data.
    var isPersonalFolder: Bool {
        switch self {
        case .downloads, .desktop, .documents: return true
        case .caches, .logs, .temporaryFiles: return false
        }
    }

    var localizedName: String {
        L(key: "category.\(rawValue).name")
    }

    var localizedDescription: String {
        L(key: "category.\(rawValue).description")
    }

    var icon: String {
        switch self {
        case .caches: return "archivebox.fill"
        case .logs: return "doc.text.fill"
        case .temporaryFiles: return "clock.arrow.circlepath"
        case .downloads: return "arrow.down.circle.fill"
        case .desktop: return "menubar.dock.rectangle"
        case .documents: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .caches: return .purple
        case .logs: return .orange
        case .temporaryFiles: return .blue
        case .downloads: return .green
        case .desktop: return .teal
        case .documents: return .indigo
        }
    }
}

// MARK: - Cleanable Item

struct CleanableItem: Identifiable {
    let id = UUID()
    let name: String
    let path: URL
    let size: Int64
    let modificationDate: Date?
    let category: ScanCategory

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modificationDate else { return L("common.unknown") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
