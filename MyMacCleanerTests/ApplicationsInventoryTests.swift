import Testing
import AppKit
@testable import MyMacCleaner

// MARK: - Applications Inventory Tests

@Suite("Applications Inventory Tests")
@MainActor
struct ApplicationsInventoryTests {
    /// Two app folders: `Alpha.app`, `Beta.app`, a hidden app and a plain file in the first;
    /// `Gamma.app` in the second.
    private func makeAppFolders() throws -> [URL] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationsInventoryTests-\(UUID().uuidString)")
        let system = root.appendingPathComponent("Applications")
        let user = root.appendingPathComponent("UserApplications")
        for folder in [system, user] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for app in ["Alpha.app", "Beta.app", ".Hidden.app"] {
            try FileManager.default.createDirectory(at: system.appendingPathComponent(app), withIntermediateDirectories: true)
        }
        try Data().write(to: system.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: user.appendingPathComponent("Gamma.app"), withIntermediateDirectories: true)
        return [system, user]
    }

    private func appInfo(_ url: URL) -> AppInfo {
        AppInfo(
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            bundleId: nil,
            version: nil,
            icon: NSImage(),
            size: 0,
            sizeCalculated: false,
            dateModified: nil,
            dateAdded: nil
        )
    }

    @Test("Installed apps are the visible .app bundles in both app folders")
    func installedAppsCoverBothFolders() throws {
        let folders = try makeAppFolders()
        defer { try? FileManager.default.removeItem(at: folders[0].deletingLastPathComponent()) }

        let names = InstalledApplications.bundleURLs(in: folders).map(\.lastPathComponent)

        #expect(names.sorted() == ["Alpha.app", "Beta.app", "Gamma.app"])
        #expect(InstalledApplications.folders.map(\.path) == [
            "/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ])
    }

    @Test("Analyze pressed during discovery finishes discovery first, so every app is sized")
    func analyzeDuringDiscoverySizesTheFullList() async throws {
        let folders = try makeAppFolders()
        defer { try? FileManager.default.removeItem(at: folders[0].deletingLastPathComponent()) }
        let viewModel = ApplicationsViewModel(appFolders: folders)
        viewModel.startBackgroundDiscovery()
        // Discovery has found one app so far.
        let firstApp = try #require(InstalledApplications.bundleURLs(in: folders).first)
        viewModel.applications = [appInfo(firstApp)]

        viewModel.startFullAnalysis()
        #expect(await waitUntil { viewModel.analysisState == .completed })

        #expect(viewModel.applications.map(\.name).sorted() == ["Alpha", "Beta", "Gamma"])
        #expect(viewModel.appsWithSizeCalculated == 3)
        #expect(viewModel.discoveryState == .completed)
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}
