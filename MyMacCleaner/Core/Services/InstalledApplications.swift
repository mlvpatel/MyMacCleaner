import Foundation

/// The one definition of an installed app: an `.app` bundle directly inside /Applications or
/// ~/Applications. Home's app count and the Applications inventory both read it, so they agree.
enum InstalledApplications {
    static let folders = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    /// The app bundles in `folders`, folder by folder; a folder that can't be read adds none.
    static func bundleURLs(in folders: [URL] = folders) -> [URL] {
        folders.flatMap { folder in
            let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .addedToDirectoryDateKey],
                options: [.skipsHiddenFiles]
            )
            return (contents ?? []).filter { $0.pathExtension == "app" }
        }
    }
}
