import Testing
import Foundation
import CryptoKit
@testable import MyMacCleaner

// MARK: - Duplicate Scanner Tests

@Suite("Duplicate Scanner Tests")
struct DuplicateScannerTests {
    private static let payload = Data(repeating: 7, count: 4_096)
    /// Matches the scanner's 64 KB read size, so the file below is read in four chunks.
    private static let hashChunkBytes = 65_536

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func scan(_ directory: URL, maxEntries: Int = 100) async -> DuplicateScanResult {
        await DuplicateScanner.shared.scan(at: directory, minSize: 1_024, maxEntries: maxEntries) { _, _ in }
    }

    @Test("Enumeration stops at the entry cap and flags the result as truncated")
    func capIsRespectedAndFlagged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["a.bin", "b.bin", "c.bin"] {
            try Self.payload.write(to: directory.appendingPathComponent(name))
        }

        let full = await scan(directory)
        let capped = await scan(directory, maxEntries: 2)

        #expect(full.isTruncated == false)
        #expect(full.skippedCloudOnlyCount == 0)
        #expect(full.groups.first?.files.count == 3)
        #expect(capped.isTruncated)
        #expect(capped.groups.flatMap(\.files).count == 2)
    }

    @Test("iCloud items whose contents are not on this Mac are skipped, so the scan never starts a download")
    func cloudOnlyItemsAreRecognised() {
        #expect(DuplicateScanner.isCloudOnly(isUbiquitous: true, downloadingStatus: .notDownloaded))
        #expect(DuplicateScanner.isCloudOnly(isUbiquitous: true, downloadingStatus: nil))
        #expect(!DuplicateScanner.isCloudOnly(isUbiquitous: true, downloadingStatus: .current))
        #expect(!DuplicateScanner.isCloudOnly(isUbiquitous: true, downloadingStatus: .downloaded))
        #expect(!DuplicateScanner.isCloudOnly(isUbiquitous: false, downloadingStatus: nil))
    }

    @Test("Hard links to one file are never reported as duplicates of each other")
    func hardLinksAreDeduped() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.bin")
        try Self.payload.write(to: original)
        try FileManager.default.linkItem(at: original, to: directory.appendingPathComponent("link.bin"))

        let linkedOnly = await scan(directory)
        try Self.payload.write(to: directory.appendingPathComponent("copy.bin"))
        let withCopy = await scan(directory)

        #expect(linkedOnly.groups.isEmpty)
        #expect(withCopy.groups.count == 1)
        #expect(withCopy.groups.first?.files.count == 2)
    }

    @Test("A full hash stops at the next chunk once cancellation is requested")
    func fullHashStopsMidFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = Data(repeating: 1, count: Self.hashChunkBytes * 4)
        let file = directory.appendingPathComponent("large.bin")
        try data.write(to: file)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        var checks = 0
        let cancelledHash = DuplicateScanner.fullHash(of: file) {
            checks += 1
            return checks > 1
        }

        #expect(cancelledHash == nil)
        #expect(checks == 2)
        #expect(DuplicateScanner.fullHash(of: file) { false } == expected)
    }

    @Test("A read error yields no hash instead of the hash of what was read")
    func readErrorYieldsNoHash() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.bin")
        try Self.payload.write(to: file)

        // Reading from a write-only handle fails with EBADF on the first chunk.
        let writeOnly = try FileHandle(forWritingTo: file)
        defer { try? writeOnly.close() }

        #expect(DuplicateScanner.fullHash(reading: writeOnly) { false } == nil)
    }
}
