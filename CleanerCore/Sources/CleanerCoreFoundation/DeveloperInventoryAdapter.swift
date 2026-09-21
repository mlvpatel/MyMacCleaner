import CleanerCore
import Foundation

public struct DeveloperInventoryAdapter: Sendable {
    private let fileExists: @Sendable (URL) -> Bool
    private let applicationsDirectory: URL

    public init(
        applicationsDirectory: URL,
        fileExists: @escaping @Sendable (URL) -> Bool
    ) {
        self.applicationsDirectory = applicationsDirectory
        self.fileExists = fileExists
    }

    public func observe() -> [DeveloperInventoryRecord] {
        var presence: [DeveloperToolID: DeveloperPresence] = [:]
        presence[.cursor] = exists("Cursor.app")
        presence[.vscode] = exists("Visual Studio Code.app")
        presence[.docker] = exists("Docker.app")
        presence[.homebrew] = .unavailable
        return DeveloperInventoryRegistry.records(presence: presence)
    }

    private func exists(_ name: String) -> DeveloperPresence {
        let url = applicationsDirectory.appendingPathComponent(name)
        return fileExists(url) ? .present : .absent
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
