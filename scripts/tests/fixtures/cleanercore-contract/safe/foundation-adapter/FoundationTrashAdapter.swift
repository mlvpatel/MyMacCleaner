import CleanerCore
import Foundation

func moveOnce(_ manager: FileManager, _ url: URL) throws {
    var resulting: NSURL?
    try manager.trashItem(at: url, resultingItemURL: &resulting)
}
