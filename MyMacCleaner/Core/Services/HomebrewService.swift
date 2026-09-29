import Foundation

// MARK: - Homebrew Models

struct HomebrewCask: Identifiable {
    let id: String
    let name: String
    let version: String
    let installedVersion: String?
    let description: String?
    let homepage: URL?
    let hasUpdate: Bool

    var displayName: String {
        name.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

struct HomebrewFormula: Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let hasUpdate: Bool
}

// MARK: - Homebrew Service

actor HomebrewService {
    private let caskDirectories = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom"
    ]
    private let formulaDirectories = [
        "/opt/homebrew/Cellar",
        "/usr/local/Cellar"
    ]
    private let executablePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    /// Detects a local Homebrew installation without launching Homebrew.
    func isHomebrewInstalled() async -> Bool {
        executablePaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Reads installed cask directory names as local filesystem evidence only.
    func listInstalledCasks() async throws -> [HomebrewCask] {
        try localDirectoryNames(in: caskDirectories).map { name in
            HomebrewCask(
                id: name,
                name: name,
                version: "",
                installedVersion: nil,
                description: nil,
                homepage: nil,
                hasUpdate: false
            )
        }
    }

    /// Unique, case-insensitively sorted entry names across directories. Internal for tests.
    nonisolated func localDirectoryNames(in directories: [String]) throws -> [String] {
        let fileManager = FileManager.default
        let names = try directories.flatMap { directory -> [String] in
            guard fileManager.fileExists(atPath: directory) else { return [] }
            return try fileManager.contentsOfDirectory(atPath: directory)
        }

        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
