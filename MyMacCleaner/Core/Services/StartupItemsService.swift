import Foundation
import SwiftUI
import SafetyContract

// MARK: - Startup Item Model

struct StartupItem: Identifiable, Hashable {
    let id: String
    let name: String
    let label: String
    let type: StartupItemType
    let path: String
    let executablePath: String?
    let isEnabled: Bool
    let isRunning: Bool
    let isSystemItem: Bool
    let developer: String?
    let bundleIdentifier: String?

    var displayName: String { name.isEmpty ? label : name }

    var icon: String { type.icon }

    var typeColor: Color {
        switch type {
        case .launchAgent: .blue
        case .launchDaemon: .orange
        case .loginItem: .green
        case .userLaunchAgent: .purple
        }
    }
}

enum StartupItemType: String, CaseIterable {
    case launchAgent
    case launchDaemon
    case loginItem
    case userLaunchAgent

    var localizedName: String { L(key: "startupItems.type.\(rawValue)") }
    var localizedDescription: String { L(key: "startupItems.typeDesc.\(rawValue)") }

    var icon: String {
        switch self {
        case .launchAgent: "person.crop.circle"
        case .launchDaemon: "gearshape.2"
        case .loginItem: "arrow.right.circle"
        case .userLaunchAgent: "person.circle"
        }
    }
}

// MARK: - Startup Items Service

actor StartupItemsService {
    static let shared = StartupItemsService()

    private init() {}

    /// Selects an inventoried item in Finder. Read-only: it never opens, runs, or changes the item.
    nonisolated func revealInFinder(_ item: StartupItem) {
        let url = URL(fileURLWithPath: item.path)
        Task { @MainActor in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func scanAllItems() async -> [StartupItem] {
        let backgroundItems = await Self.parseBackgroundItems()
        let runningLabels = await Self.parseLaunchctlItems()
        let directoryItems = scanLaunchAgentDirectories(runningLabels: runningLabels)
        let deduplicated = Dictionary(
            (backgroundItems + directoryItems).map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        return deduplicated.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // SAFETY-AUDIT: fixed read-only process adapter — /usr/bin/sfltool dumpbtm
    private nonisolated static func parseBackgroundItems() async -> [StartupItem] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
                process.arguments = ["dumpbtm"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice

                guard (try? process.run()) != nil else {
                    SafetyDiagnosticLogger.emit(
                        RedactingDiagnostic.record(
                            event: .startupBackgroundItemsUnavailable,
                            sensitiveClasses: [.command, .error]
                        )
                    )
                    continuation.resume(returning: [])
                    return
                }

                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8)
                else {
                    SafetyDiagnosticLogger.emit(
                        RedactingDiagnostic.record(
                            event: .startupBackgroundItemsUnavailable,
                            sensitiveClasses: [.command, .error]
                        )
                    )
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: parseBTMOutput(text))
            }
        }
    }

    // SAFETY-AUDIT: fixed read-only process adapter — /bin/launchctl list
    private nonisolated static func parseLaunchctlItems() async -> Set<String> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["list"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice

                guard (try? process.run()) != nil else {
                    SafetyDiagnosticLogger.emit(
                        RedactingDiagnostic.record(
                            event: .startupLaunchctlItemsUnavailable,
                            sensitiveClasses: [.command, .error]
                        )
                    )
                    continuation.resume(returning: [])
                    return
                }

                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8)
                else {
                    SafetyDiagnosticLogger.emit(
                        RedactingDiagnostic.record(
                            event: .startupLaunchctlItemsUnavailable,
                            sensitiveClasses: [.command, .error]
                        )
                    )
                    continuation.resume(returning: [])
                    return
                }

                let labels: [String] = text.split(separator: "\n").dropFirst().compactMap { line in
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                    guard fields.count >= 3, !fields[2].isEmpty else { return nil }
                    return String(fields[2])
                }
                continuation.resume(returning: Set(labels))
            }
        }
    }

    private func scanLaunchAgentDirectories(runningLabels: Set<String>) -> [StartupItem] {
        let roots: [(String, StartupItemType, Bool)] = [
            (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path, .userLaunchAgent, false),
            ("/Library/LaunchAgents", .launchAgent, false),
            ("/Library/LaunchDaemons", .launchDaemon, true)
        ]

        return roots.flatMap { path, type, isSystemItem -> [StartupItem] in
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }

            return names.compactMap { filename in
                guard filename.hasSuffix(".plist") else { return nil }
                let itemPath = URL(fileURLWithPath: path).appendingPathComponent(filename).path
                return Self.parseLaunchItem(
                    at: itemPath,
                    type: type,
                    isSystemItem: isSystemItem,
                    runningLabels: runningLabels
                )
            }
        }
    }

    /// Parses `sfltool dumpbtm` output. Internal for tests.
    nonisolated static func parseBTMOutput(_ output: String) -> [StartupItem] {
        var items: [StartupItem] = []
        var current: [String: String] = [:]

        func appendCurrentItem() {
            guard let identifier = current["Identifier"],
                  let name = current["Name"],
                  !identifier.hasPrefix("com.apple.")
            else { return }

            let type: StartupItemType
            let typeValue = current["Type", default: ""]
            if typeValue.contains("login item") {
                type = .loginItem
            } else if typeValue.contains("daemon") {
                type = .launchDaemon
            } else if typeValue.contains("agent") {
                type = .launchAgent
            } else {
                return
            }

            let path = current["URL", default: ""].replacingOccurrences(of: "file://", with: "")
            items.append(
                StartupItem(
                    id: "btm:\(identifier)",
                    name: name,
                    label: identifier,
                    type: type,
                    path: path,
                    executablePath: current["Executable Path"],
                    isEnabled: current["Disposition", default: ""].contains("enabled"),
                    isRunning: false,
                    isSystemItem: false,
                    developer: nil,
                    bundleIdentifier: current["Bundle Identifier"]
                )
            )
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("#") && value.contains(":") {
                appendCurrentItem()
                current = [:]
            } else if let separator = value.firstIndex(of: ":") {
                let key = value[..<separator].trimmingCharacters(in: .whitespaces)
                let itemValue = value[value.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                current[key] = itemValue
            }
        }
        appendCurrentItem()

        return items
    }

    /// Reads one launchd plist. Internal for tests.
    nonisolated static func parseLaunchItem(
        at path: String,
        type: StartupItemType,
        isSystemItem: Bool,
        runningLabels: Set<String>
    ) -> StartupItem? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String
        else {
            return nil
        }

        let program = plist["Program"] as? String
        let arguments = plist["ProgramArguments"] as? [String]
        let executablePath = program ?? arguments?.first
        let name = label.components(separatedBy: ".").last ?? label

        return StartupItem(
            id: path,
            name: name,
            label: label,
            type: type,
            path: path,
            executablePath: executablePath,
            isEnabled: !(plist["Disabled"] as? Bool ?? false),
            isRunning: runningLabels.contains(label),
            isSystemItem: isSystemItem,
            developer: nil,
            bundleIdentifier: label
        )
    }
}
