import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Shared Fixtures

private enum TemporaryDirectory {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Startup Items Parsing Tests

@Suite("Startup Items Parsing Tests")
struct StartupItemsParsingTests {
    private static let btmOutput = """
    ========================
     Records for UID 501 :
    ========================
     #1:
                     UUID: 11111111-1111-1111-1111-111111111111
                     Name: Example Helper
                     Type: login item
                     Disposition: [enabled, allowed, visible, notified]
                     Identifier: com.example.helper
                     URL: file:///Applications/Example.app/Contents/Library/LoginItems/Helper.app/
          Bundle Identifier: com.example.helper
     #2:
                     Name: Apple Agent
                     Type: agent
                     Disposition: [enabled]
                     Identifier: com.apple.something
     #3:
                     Name: Sync Daemon
                     Type: daemon
                     Disposition: [disabled]
                     Identifier: org.sync.daemon
                     Executable Path: /Library/PrivilegedHelperTools/org.sync.daemon
     #4:
                     Name: Mystery
                     Type: developer
                     Identifier: dev.mystery
    """

    @Test("BTM output keeps third-party login items, agents and daemons only")
    func parsesThirdPartyItems() {
        let items = StartupItemsService.parseBTMOutput(Self.btmOutput)

        #expect(items.map(\.label) == ["com.example.helper", "org.sync.daemon"])
    }

    @Test("BTM fields map to type, path, enablement and bundle identifier")
    func mapsBTMFields() throws {
        let items = StartupItemsService.parseBTMOutput(Self.btmOutput)
        let helper = try #require(items.first)
        let daemon = try #require(items.last)

        #expect(helper.id == "btm:com.example.helper")
        #expect(helper.type == .loginItem)
        #expect(helper.isEnabled)
        #expect(helper.path == "/Applications/Example.app/Contents/Library/LoginItems/Helper.app/")
        #expect(helper.bundleIdentifier == "com.example.helper")
        #expect(daemon.type == .launchDaemon)
        #expect(daemon.isEnabled == false)
        #expect(daemon.executablePath == "/Library/PrivilegedHelperTools/org.sync.daemon")
    }

    @Test("Empty BTM output yields no items")
    func emptyOutputYieldsNothing() {
        #expect(StartupItemsService.parseBTMOutput("").isEmpty)
    }

    @Test("Launchd plists map label, program, disabled flag and running state")
    func parsesLaunchItemPlist() throws {
        let directory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("org.example.agent.plist").path
        let plist: [String: Any] = [
            "Label": "org.example.agent",
            "ProgramArguments": ["/usr/local/bin/agent", "--flag"],
            "Disabled": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path))

        let item = try #require(StartupItemsService.parseLaunchItem(
            at: path,
            type: .userLaunchAgent,
            isSystemItem: false,
            runningLabels: ["org.example.agent"]
        ))

        #expect(item.name == "agent")
        #expect(item.executablePath == "/usr/local/bin/agent")
        #expect(item.isEnabled == false)
        #expect(item.isRunning)
        #expect(item.type == .userLaunchAgent)
    }

    @Test("Unreadable or label-less plists are skipped")
    func skipsInvalidPlists() throws {
        let directory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("broken.plist").path
        try Data("not a plist".utf8).write(to: URL(fileURLWithPath: path))

        #expect(StartupItemsService.parseLaunchItem(at: path, type: .launchAgent, isSystemItem: true, runningLabels: []) == nil)
        #expect(StartupItemsService.parseLaunchItem(at: directory.appendingPathComponent("missing.plist").path, type: .launchAgent, isSystemItem: true, runningLabels: []) == nil)
    }
}

// MARK: - Port Parsing Tests

@Suite("Port Parsing Tests")
struct PortParsingTests {
    private static let lsofOutput = """
    COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    rapportd    512 me    8u  IPv4 0x1111111111111111      0t0  TCP *:49152 (LISTEN)
    Safari     1024 me   30u  IPv6 0x2222222222222222      0t0  TCP [::1]:52000->[::1]:443 (ESTABLISHED)
    broken     notapid me  1u  IPv4 0x3333333333333333      0t0  TCP *:80 (LISTEN)
    short line
    """

    @Test("lsof output becomes listening and established connections")
    func parsesConnections() throws {
        let connections = PortManagementViewModel.parsePorts(Self.lsofOutput)

        #expect(connections.count == 2)
        let listener = try #require(connections.first)
        #expect(listener.processName == "rapportd")
        #expect(listener.pid == 512)
        #expect(listener.localAddress == "*")
        #expect(listener.localPort == 49152)
        #expect(listener.state == "LISTEN")
        #expect(listener.remoteAddress == nil)

        let established = try #require(connections.last)
        #expect(established.localAddress == "[::1]")
        #expect(established.localPort == 52000)
        #expect(established.remotePort == 443)
        #expect(established.state == "ESTABLISHED")
    }

    @Test("Address parsing splits on the last colon and rejects missing ports", arguments: [
        ("127.0.0.1:8080", "127.0.0.1", 8080),
        ("[fe80::1]:22", "[fe80::1]", 22),
        ("*:abc", "*", 0),
        ("no-port", "*", 0),
    ])
    func parsesAddressPort(input: String, address: String, port: Int) {
        let parsed = PortManagementViewModel.parseAddressPort(input)
        #expect(parsed.address == address)
        #expect(parsed.port == port)
    }

    @Test("Header-only output yields no connections")
    func headerOnlyYieldsNothing() {
        #expect(PortManagementViewModel.parsePorts("COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME").isEmpty)
    }
}

// MARK: - System Health Logic Tests

@Suite("System Health Logic Tests")
struct SystemHealthLogicTests {
    @Test("diskutil output classifies SMART status")
    func classifiesDiskInfo() {
        #expect(SystemHealthViewModel.parseDiskInfo("   SMART Status:   Verified\n") == .verified)
        #expect(SystemHealthViewModel.parseDiskInfo("   SMART Status:   Not Supported\n") == .notSupported)
        #expect(SystemHealthViewModel.parseDiskInfo("Device Node: /dev/disk3s1") == .unknown)
    }

    @Test("Health score weights passed fully, warnings half, failures zero")
    func scoresChecks() {
        let cases: [([HealthCheck.Status], Int, SystemHealthViewModel.HealthStatus)] = [
            ([], 0, .unknown),
            ([.passed, .passed], 100, .excellent),
            ([.passed, .passed, .passed, .warning], 87, .good),
            ([.passed, .failed], 50, .fair),
            ([.warning, .failed, .checking], 16, .poor),
        ]
        for (statuses, score, status) in cases {
            let result = SystemHealthViewModel.healthScore(for: statuses)
            #expect(result.score == score, "score for \(statuses)")
            #expect(result.status == status, "status for \(statuses)")
        }
    }

    @Test("The macOS version row is a fact for reference and never moves the score")
    func macOSVersionIsInformational() {
        let check = SystemHealthViewModel.macOSVersionCheck(OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 0))

        #expect(check.status == .info)
        #expect(check.description == LFormat("systemHealth.check.macOSVersion.info %@", "14.1.0"))
        let withVersion = SystemHealthViewModel.healthScore(for: [.passed, .warning, check.status])
        #expect(withVersion.score == SystemHealthViewModel.healthScore(for: [.passed, .warning]).score)
    }

    @Test("A diskutil failure reads as unavailable, never as healthy")
    func diskutilFailureIsUnavailable() {
        let result = SystemHealthViewModel.diskHealthResult(.unavailable)

        #expect(result.status == .unavailable)
        #expect(result.key == "systemHealth.check.diskHealth.unavailable")
    }

    @Test("A check that couldn't run keeps the verdict from saying healthy")
    func unavailableCheckBlocksHealthyVerdict() {
        let statuses: [HealthCheck.Status] = [.passed, .passed, .passed, .passed, .unavailable, .info]

        #expect(SystemHealthViewModel.healthScore(for: statuses).status != .excellent)
        #expect(SystemHealthViewModel.summary(for: statuses) == LFormat("systemHealth.summary.incomplete %lld %lld", 4, 1))
        #expect(SystemHealthViewModel.summary(for: [.passed, .info]) == LFormat("systemHealth.summary.passed %lld", 1))
    }
}

// MARK: - Orphaned Files Heuristic Tests

@Suite("Orphaned Files Heuristic Tests")
struct OrphanedFilesHeuristicTests {
    private let scanner = OrphanedFilesScanner.shared

    @Test("Bundle identifiers are recognised from reverse-DNS names and group containers", arguments: [
        ("com.example.App.plist", "com.example.App"),
        ("io.tool.Helper.savedState", "io.tool.Helper"),
        ("group.com.example.shared", "com.example.shared"),
        ("Example Folder", nil),
    ] as [(String, String?)])
    func extractsBundleIdentifier(name: String, expected: String?) {
        #expect(scanner.extractBundleId(from: name) == expected)
    }

    @Test("App names come from the last bundle component", arguments: [
        ("com.example.MyApp.plist", "MyApp"),
        ("org.tool.helper", "Helper"),
        ("Slack", "Slack"),
    ])
    func extractsAppName(name: String, expected: String) {
        #expect(scanner.extractAppName(from: name) == expected)
    }

    @Test("Apple and system items are never reported as orphans")
    func excludesSystemItems() {
        #expect(scanner.isSystemItem("com.apple.Safari.plist"))
        #expect(scanner.isSystemItem("Xcode"))
        #expect(scanner.isSystemItem("com.example.helper") == false)
    }
}

// MARK: - Homebrew Inventory Tests

@Suite("Homebrew Inventory Tests")
struct HomebrewInventoryTests {
    @Test("Directory names are merged, de-duplicated and sorted case-insensitively")
    func mergesDirectoryNames() throws {
        let first = try TemporaryDirectory.make()
        let second = try TemporaryDirectory.make()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        for name in ["zed", "Alpha"] {
            try FileManager.default.createDirectory(at: first.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        for name in ["beta", "zed"] {
            try FileManager.default.createDirectory(at: second.appendingPathComponent(name), withIntermediateDirectories: false)
        }

        let names = try HomebrewService().localDirectoryNames(in: [first.path, second.path, "/nonexistent/Caskroom"])

        #expect(names == ["Alpha", "beta", "zed"])
    }
}

// MARK: - Browser Inventory Tests

@Suite("Browser Inventory Tests")
struct BrowserInventoryTests {
    private func item(_ browser: BrowserType, _ type: BrowserDataType, _ size: Int64) -> BrowserDataItem {
        BrowserDataItem(browser: browser, dataType: type, path: URL(fileURLWithPath: "/tmp/fixture"), size: size)
    }

    @Test("Summaries total bytes per data type and per browser")
    func summarisesItems() async {
        let items = [
            item(.safari, .cache, 100),
            item(.chrome, .cache, 50),
            item(.chrome, .cookies, 5),
        ]
        let service = BrowserCleanerService.shared

        let byType = await service.getSummary(for: items)
        let byBrowser = await service.getBrowserSummary(for: items)

        #expect(byType[.cache] == 150)
        #expect(byType[.cookies] == 5)
        #expect(byBrowser[.chrome] == 55)
        #expect(byBrowser[.safari] == 100)
    }

    @Test("Directory size is nil for missing or empty folders and positive otherwise")
    func measuresDirectorySize() throws {
        let directory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = BrowserCleanerService.shared

        #expect(service.getDirectorySize(at: directory.appendingPathComponent("missing").path) == nil)
        #expect(service.getDirectorySize(at: directory.path) == nil)

        try Data(repeating: 1, count: 8_192).write(to: directory.appendingPathComponent("cache.bin"))
        #expect((service.getDirectorySize(at: directory.path) ?? 0) > 0)
    }

    @Test("A browser whose data folder exists but will not open is unreadable; a missing folder is not")
    func reportsRefusedDataFolders() throws {
        let home = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: home) }
        for browser in [BrowserType.safari, .firefox] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(browser.dataFolder),
                withIntermediateDirectories: true
            )
        }
        // Safari's folder is refused, Firefox's opens and Chrome has none.
        let probe = OpenablePaths([home.appendingPathComponent(BrowserType.firefox.dataFolder).path])

        let unreadable = BrowserCleanerService.unreadableBrowsers(BrowserType.allCases, home: home.path, probe: probe)

        #expect(unreadable == [.safari])
    }

    @Test("Browser Privacy keeps the browsers its scan could not read")
    @MainActor
    func viewModelKeepsUnreadableBrowsers() async {
        let viewModel = BrowserPrivacyViewModel(scanBrowsers: {
            BrowserScan(items: [], unreadableBrowsers: [.safari])
        })

        viewModel.scan()
        for _ in 0..<200 where !viewModel.hasScanned {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(viewModel.hasScanned)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.unreadableBrowsers == [.safari])
    }
}

/// A path "opens" only when it is listed, so permission refusals can be tested without real ones.
private struct OpenablePaths: PermissionProbing {
    let paths: Set<String>

    init(_ paths: Set<String>) {
        self.paths = paths
    }

    func canOpenForReading(atPath path: String) -> Bool {
        paths.contains(path)
    }
}

// MARK: - Trash Inventory Tests

@Suite("Trash Inventory Tests")
struct TrashInventoryTests {
    @Test("Trash measurement distinguishes empty, sized and unreadable folders")
    func measuresTrash() async throws {
        let directory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: directory) }

        let empty = await TrashInventoryReader.measure(at: directory)
        #expect(empty == .measured(bytes: 0))

        try Data(repeating: 1, count: 8_192).write(to: directory.appendingPathComponent("a.bin"))
        let nested = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data(repeating: 1, count: 8_192).write(to: nested.appendingPathComponent("b.bin"))
        guard case let .measured(bytes) = await TrashInventoryReader.measure(at: directory) else {
            Issue.record("Expected a measured Trash")
            return
        }
        #expect(bytes >= 16_384)

        let missing = await TrashInventoryReader.measure(at: directory.appendingPathComponent("missing"))
        #expect(missing == .unavailable)
    }
}

// MARK: - Directory Size Tests

@Suite("Directory Size Tests")
struct DirectorySizeTests {
    private static let payload = Data(repeating: 1, count: 8_192)

    private func allocatedBytes(of file: URL) throws -> Int64 {
        Int64(try #require(try file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize))
    }

    @Test("Regular files are summed, hidden ones included, and symlinks are never followed")
    func sumsRegularFilesOnly() throws {
        let directory = try TemporaryDirectory.make()
        let outside = try TemporaryDirectory.make()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        let visible = directory.appendingPathComponent("cache.bin")
        let hidden = directory.appendingPathComponent(".index")
        try Self.payload.write(to: visible)
        try Self.payload.write(to: hidden)
        try Data(repeating: 2, count: 65_536).write(to: outside.appendingPathComponent("big.bin"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: outside)

        let total = DirectorySize.allocatedBytes(at: directory)

        #expect(total == (try allocatedBytes(of: visible)) + (try allocatedBytes(of: hidden)))
    }

    @Test("Sizing stops at the entry cap")
    func capIsRespected() throws {
        let directory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["a.bin", "b.bin", "c.bin"] {
            try Self.payload.write(to: directory.appendingPathComponent(name))
        }

        let full = try #require(DirectorySize.allocatedBytes(at: directory))
        let capped = try #require(DirectorySize.allocatedBytes(at: directory, maxEntries: 2))

        #expect(full > 0)
        #expect(capped * 3 == full * 2)
    }

    @Test("Sizing stops once its task is cancelled")
    func honoursCancellation() async throws {
        let directory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.payload.write(to: directory.appendingPathComponent("a.bin"))

        let task = Task { () -> Int64? in
            withUnsafeCurrentTask { $0?.cancel() }
            return DirectorySize.allocatedBytes(at: directory)
        }

        #expect(await task.value == 0)
        #expect((DirectorySize.allocatedBytes(at: directory) ?? 0) > 0)
    }
}
