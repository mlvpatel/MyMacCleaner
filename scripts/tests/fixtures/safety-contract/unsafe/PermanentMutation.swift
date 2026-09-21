import Foundation

func permanentlyRemove(_ url: URL) throws {
    try FileManager.default.removeItem(at: url)
}
