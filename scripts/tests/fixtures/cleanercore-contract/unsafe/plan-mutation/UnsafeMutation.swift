import Foundation

struct UnsafeMutation {
    func go(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
