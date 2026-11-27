import CleanerCore
import Foundation

func moveTwice(_ manager: FileManager, _ url: URL) throws {
    var resulting: NSURL?
    try manager.trashItem(at: url, resultingItemURL: &resulting)
    try manager.trashItem(at: url, resultingItemURL: &resulting)
}
