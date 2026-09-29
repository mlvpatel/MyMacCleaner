import Testing
import Foundation
@testable import MyMacCleaner

/// C6: Docker.raw is sparse, so its disk use must come from allocated bytes, never
/// its logical size, and a non-regular file must not be measured.
@Suite("Docker Disk Image Size Tests")
struct DockerDiskImageSizeTests {
    private static let logicalBytes: UInt64 = 1 << 30

    @Test("A sparse file reports its allocated bytes, far below its logical size")
    func sparseFileReportsAllocatedBytes() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("sparse.raw")
        #expect(FileManager.default.createFile(atPath: image.path, contents: Data("x".utf8)))
        let handle = try FileHandle(forWritingTo: image)
        try handle.truncate(atOffset: Self.logicalBytes)
        try handle.close()

        let allocated = try #require(CleanerCoreLiveScan.fileAllocatedBytes(of: image))

        #expect(allocated > 0)
        #expect(UInt64(allocated) < Self.logicalBytes / 16)
    }

    @Test("A symlink or a missing file is not measured")
    func nonRegularFilesAreNotMeasured() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.raw")
        #expect(FileManager.default.createFile(atPath: target.path, contents: Data(repeating: 1, count: 8_192)))
        let link = directory.appendingPathComponent("link.raw")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(CleanerCoreLiveScan.fileAllocatedBytes(of: link) == nil)
        #expect(CleanerCoreLiveScan.fileAllocatedBytes(of: directory.appendingPathComponent("missing.raw")) == nil)
        #expect(CleanerCoreLiveScan.fileAllocatedBytes(of: target) != nil)
    }

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("docker-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
