import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

/// C5 wiring: open files reported by the fixed `lsof` listing mark scanned files in-use.
@Suite("Open File Activity Tests")
struct OpenFileActivityTests {
    private static let caches = "/Users/u/Library/Caches"

    private static let listing = """
    p123
    f4
    n/Users/u/Library/Caches/com.apple.iconservices.store/a.bin
    f5
    n/Users/u/Library/Caches/Caf\\xc3\\xa9/b.db
    f6
    n/Users/u/Documents/x.txt
    f7
    n/Users/u/Library/CachesX/sibling.bin
    fcwd
    n/
    p456
    f3
    n/Users/u/Library/Caches
    """

    @Test("Parser keeps only files strictly under the scanned roots and decodes escapes")
    func parserKeepsFilesUnderRoots() {
        let paths = OpenFileActivityReader.parseOpenFilePaths(Self.listing, under: [Self.caches])

        #expect(paths == [
            "/Users/u/Library/Caches/com.apple.iconservices.store/a.bin",
            "/Users/u/Library/Caches/Café/b.db",
        ])
    }

    @Test("lsof byte escapes decode to UTF-8; malformed escapes stay literal")
    func lsofNamesDecode() {
        #expect(OpenFileActivityReader.decodeLsofName("Caf\\xc3\\xa9") == "Café")
        #expect(OpenFileActivityReader.decodeLsofName("plain/path") == "plain/path")
        #expect(OpenFileActivityReader.decodeLsofName("odd\\xzz") == "odd\\xzz")
    }

    @Test("Snapshot marks exactly the open file under its declared root")
    func snapshotMatchesRootAndComponents() throws {
        let root = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryCaches).id
        let other = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryLogs).id
        let snapshot = OpenFileActivityReader.snapshot(roots: [root: Self.caches], listing: Self.listing)

        #expect(snapshot.isFileOpen(rootID: root, components: ["com.apple.iconservices.store", "a.bin"]))
        #expect(snapshot.isFileOpen(rootID: root, components: ["com.apple.iconservices.store", "b.bin"]) == false)
        #expect(snapshot.isFileOpen(rootID: other, components: ["com.apple.iconservices.store", "a.bin"]) == false)
        #expect(snapshot.isFileOpen(rootID: root, components: []) == false)
    }

    @Test("A failed lsof read yields an empty snapshot, so activity falls back to today's rule")
    func failedListingMarksNothingOpen() throws {
        let root = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryCaches).id
        let snapshot = OpenFileActivityReader.snapshot(roots: [root: Self.caches], listing: nil)

        #expect(snapshot.isFileOpen(rootID: root, components: ["com.apple.iconservices.store", "a.bin"]) == false)
    }

    @Test("Roots resolve to the real path lsof reports")
    func rootsResolveSymlinks() {
        #expect(OpenFileActivityReader.canonicalPath(URL(fileURLWithPath: "/tmp")) == "/private/tmp")
        #expect(OpenFileActivityReader.canonicalPath(URL(fileURLWithPath: "/private/tmp/", isDirectory: true)) == "/private/tmp")
    }
}
