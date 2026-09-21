import AppKit
import CleanerCore
import Foundation

func revealOnce(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}
