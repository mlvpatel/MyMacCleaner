import SwiftUI

// MARK: - Port Management View Model

@MainActor
final class PortManagementViewModel: ObservableObject {
    @Published var connections: [NetworkConnection] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var filterType: FilterType = .all
    /// When the shown list was read; nil before a read and after a failed one.
    @Published private(set) var lastRead: Date?
    /// True when the last read failed, so the page never shows that as "no connections".
    @Published private(set) var isUnavailable = false

    /// Readable so tests can await a refresh instead of sleeping.
    private(set) var refreshTask: Task<Void, Never>?
    /// True once a refresh has finished, so only the first visit loads on its own.
    private var hasLoaded = false
    /// nil means unavailable, as `ReadOnlyProcess.run` reports it.
    private let readPorts: @Sendable () async -> [NetworkConnection]?

    init(readPorts: @escaping @Sendable () async -> [NetworkConnection]? = { await PortManagementViewModel.readPorts() }) {
        self.readPorts = readPorts
    }

    enum FilterType: String, CaseIterable {
        case all
        case listening
        case established

        var icon: String {
            switch self {
            case .all: "network"
            case .listening: "antenna.radiowaves.left.and.right"
            case .established: "link"
            }
        }

        var localizedName: String { L("portManagement.filter.\(rawValue)") }
    }

    var filteredConnections: [NetworkConnection] {
        let matchingSearch = connections.filter { connection in
            searchText.isEmpty ||
                connection.processName.localizedCaseInsensitiveContains(searchText) ||
                String(connection.localPort).contains(searchText) ||
                (connection.remoteAddress?.contains(searchText) ?? false)
        }

        return matchingSearch.filter { connection in
            switch filterType {
            case .all: true
            case .listening: connection.state == "LISTEN"
            case .established: connection.state == "ESTABLISHED"
            }
        }
        .sorted { $0.localPort < $1.localPort }
    }

    var listeningCount: Int { connections.filter { $0.state == "LISTEN" }.count }
    var establishedCount: Int { connections.filter { $0.state == "ESTABLISHED" }.count }

    /// Reads ports on the page's first appearance instead of at app launch.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        refreshConnections()
    }

    func refreshConnections() {
        guard !isLoading else { return }
        isLoading = true
        refreshTask = Task { [readPorts] in
            let ports = await readPorts()
            // Cancelling the refresh stops lsof; its output is dropped.
            guard !Task.isCancelled else { return }
            connections = ports ?? []
            isUnavailable = ports == nil
            lastRead = ports == nil ? nil : Date()
            hasLoaded = true
            refreshTask = nil
            isLoading = false
        }
    }

    /// Abandons an in-flight refresh, keeping the last known connections.
    func cancelRefresh() {
        guard isLoading else { return }
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
    }

    // SAFETY-AUDIT: fixed read-only process adapter — /usr/sbin/lsof -iTCP -sTCP:LISTEN,ESTABLISHED -n -P
    nonisolated static func readPorts() async -> [NetworkConnection]? {
        guard let data = await ReadOnlyProcess.run(.tcpPorts),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return parsePorts(text)
    }

    /// Parses `lsof -iTCP` output. Internal for tests.
    nonisolated static func parsePorts(_ output: String) -> [NetworkConnection] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9, let pid = Int32(parts[1]) else { return nil }

            let endpoints = parts[8]
            let state = parts.dropFirst(9).first?.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            let localAndRemote = endpoints.components(separatedBy: "->")
            let local = parseAddressPort(localAndRemote[0])
            guard local.port > 0 else { return nil }

            let remote = localAndRemote.count == 2 ? parseAddressPort(localAndRemote[1]) : nil
            return NetworkConnection(
                processName: parts[0],
                pid: pid,
                localAddress: local.address,
                localPort: local.port,
                remoteAddress: remote?.address,
                remotePort: remote?.port,
                state: remote == nil ? "LISTEN" : state ?? "ESTABLISHED",
                protocol: "TCP"
            )
        }
    }

    nonisolated static func parseAddressPort(_ value: String) -> (address: String, port: Int) {
        guard let separator = value.lastIndex(of: ":") else { return ("*", 0) }
        let address = String(value[..<separator])
        let port = Int(value[value.index(after: separator)...]) ?? 0
        return (address, port)
    }
}

// MARK: - Network Connection Model

struct NetworkConnection: Identifiable, Equatable {
    let id = UUID()
    let processName: String
    let pid: Int32
    let localAddress: String
    let localPort: Int
    let remoteAddress: String?
    let remotePort: Int?
    let state: String
    let `protocol`: String

    var stateColor: Color {
        switch state {
        case "LISTEN": .green
        case "ESTABLISHED": .blue
        case "CLOSE_WAIT", "TIME_WAIT": .orange
        default: .gray
        }
    }

    var formattedLocal: String { "\(localAddress):\(localPort)" }

    var formattedRemote: String? {
        guard let remoteAddress, let remotePort else { return nil }
        return "\(remoteAddress):\(remotePort)"
    }
}
