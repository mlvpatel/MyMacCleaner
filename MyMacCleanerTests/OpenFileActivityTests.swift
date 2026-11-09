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
        let paths = OpenFileActivityReader.parseOpenFilePaths(Data(Self.listing.utf8), under: [Self.caches])

        #expect(paths == [
            "/Users/u/Library/Caches/com.apple.iconservices.store/a.bin",
            "/Users/u/Library/Caches/Café/b.db",
        ])
    }

    @Test("lsof byte escapes decode to UTF-8; malformed escapes stay literal")
    func lsofNamesDecode() {
        #expect(OpenFileActivityReader.decodeLsofName("Caf\\xc3\\xa9".utf8) == "Café")
        #expect(OpenFileActivityReader.decodeLsofName("plain/path".utf8) == "plain/path")
        #expect(OpenFileActivityReader.decodeLsofName("odd\\xzz".utf8) == "odd\\xzz")
    }

    @Test("Snapshot marks exactly the open file under its declared root")
    func snapshotMatchesRootAndComponents() throws {
        let root = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryCaches).id
        let other = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryLogs).id
        let snapshot = OpenFileActivityReader.snapshot(roots: [root: Self.caches], listing: Data(Self.listing.utf8))

        #expect(snapshot.isFileOpen(rootID: root, components: ["com.apple.iconservices.store", "a.bin"]))
        #expect(snapshot.isFileOpen(rootID: root, components: ["com.apple.iconservices.store", "b.bin"]) == false)
        #expect(snapshot.isFileOpen(rootID: other, components: ["com.apple.iconservices.store", "a.bin"]) == false)
        #expect(snapshot.isFileOpen(rootID: root, components: []) == false)
    }

    /// An open file is never eligible (CleanerCore `ProcessActivityContractTests`), so counting every
    /// file in a Trash-eligible root as open holds all of them back for the run: it only narrows.
    @Test("An unavailable listing fails closed for Trash-eligible roots only")
    func unavailableListingFailsClosed() throws {
        let caches = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryCaches).id
        let documents = try GeneralMacScopeCatalog.current.declaredRoot(for: .userDocuments).id
        let roots = [caches: Self.caches, documents: "/Users/u/Documents"]

        let unavailable = OpenFileActivityReader.snapshot(roots: roots, listing: nil)
        #expect(unavailable.isListingAvailable == false)
        #expect(unavailable.isFileOpen(rootID: caches, components: ["com.apple.iconservices.store", "a.bin"]))
        // Documents is never Trash-eligible, so its activity still comes from the modification time.
        #expect(unavailable.isFileOpen(rootID: documents, components: ["x.txt"]) == false)

        let emptyListing = OpenFileActivityReader.snapshot(roots: roots, listing: Data())
        #expect(emptyListing.isListingAvailable)
        #expect(emptyListing.isFileOpen(rootID: caches, components: ["com.apple.iconservices.store", "a.bin"]) == false)
    }

    @Test("Roots resolve to the real path lsof reports")
    func rootsResolveSymlinks() {
        #expect(OpenFileActivityReader.canonicalPath(URL(fileURLWithPath: "/tmp")) == "/private/tmp")
        #expect(OpenFileActivityReader.canonicalPath(URL(fileURLWithPath: "/private/tmp/", isDirectory: true)) == "/private/tmp")
    }
}
