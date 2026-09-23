import CleanerCore
import Foundation

public struct DeveloperInventoryAdapter: Sendable {
    private let applicationDirectories: [URL]
    private let homeDirectory: URL
    private let fileExists: @Sendable (URL) -> Bool
    private let directoryAllocatedBytes: @Sendable (URL) -> Int?

    private static let applications: [(DeveloperToolID, String)] = [
        (.cursor, "Cursor.app"),
        (.vscode, "Visual Studio Code.app"),
        (.docker, "Docker.app"),
        (.zed, "Zed.app"),
        (.windsurf, "Windsurf.app"),
        (.chatgpt, "ChatGPT.app"),
        (.ollama, "Ollama.app"),
        (.lmStudio, "LM Studio.app")
    ]

    private static let dotfileRoots: [(DeveloperToolID, String)] = [
        (.claudeConfig, ".claude"),
        (.codex, ".codex"),
        (.gemini, ".gemini"),
        (.continueConfig, ".continue"),
        (.cursorConfig, ".cursor")
    ]

    public init(
        applicationsDirectory: URL,
        additionalApplicationDirectories: [URL] = [],
        homeDirectory: URL,
        fileExists: @escaping @Sendable (URL) -> Bool,
        directoryAllocatedBytes: @escaping @Sendable (URL) -> Int? = { _ in nil }
    ) {
        applicationDirectories = [applicationsDirectory] + additionalApplicationDirectories
        self.homeDirectory = homeDirectory
        self.fileExists = fileExists
        self.directoryAllocatedBytes = directoryAllocatedBytes
    }

    public func observe() -> [DeveloperInventoryRecord] {
        var presence: [DeveloperToolID: DeveloperPresence] = [:]
        var sizes: [DeveloperToolID: Int] = [:]

        for (tool, bundleName) in Self.applications {
            presence[tool] = appPresence(bundleName)
        }
        presence[.homebrew] = .unavailable

        for (tool, dotfileName) in Self.dotfileRoots {
            let url = homeDirectory.appendingPathComponent(dotfileName, isDirectory: true)
            if fileExists(url) {
                presence[tool] = .present
                if let bytes = directoryAllocatedBytes(url) {
                    sizes[tool] = bytes
                }
            } else {
                presence[tool] = .absent
            }
        }

        return DeveloperInventoryRegistry.records(presence: presence, sizes: sizes)
    }

    private func appPresence(_ bundleName: String) -> DeveloperPresence {
        for directory in applicationDirectories {
            if fileExists(directory.appendingPathComponent(bundleName)) {
                return .present
            }
        }
        return .absent
    }
}

public struct DockerDiskUsageAdapter: Sendable {
    public enum Mode: Equatable, Sendable {
        case presenceOnly
    }

    public let mode: Mode

    public init() {
        mode = .presenceOnly
    }

    public func snapshot(presence: DeveloperPresence) -> DeveloperInventoryRecord {
        DeveloperInventoryRecord(tool: .docker, presence: presence)
    }
}
