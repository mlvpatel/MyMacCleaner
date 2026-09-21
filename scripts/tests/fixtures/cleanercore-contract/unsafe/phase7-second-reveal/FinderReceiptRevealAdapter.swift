import AppKit
import CleanerCore
import Foundation

func revealTwice(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}
