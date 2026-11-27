import AppKit
import Combine

/// Lets Quit (menu bar, Command-Q, log out) through, except while items are moving to the Trash.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quitGuard: TrashRunQuitGuard?

    /// Every window shares one Adaptive view model, so the first window to appear sets the guard.
    func attach(_ viewModel: AdaptiveExperienceViewModel) {
        guard quitGuard == nil else { return }
        quitGuard = TrashRunQuitGuard(viewModel: viewModel)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitGuard?.shouldTerminate() ?? .terminateNow
    }
}

/// What Quit does during a Trash run. It never quits mid-item: the user either keeps the run going,
/// or stops it before the next item (moved items stay in the Trash and in the receipt) and the app
/// quits once the run has ended and its receipt is written.
@MainActor
final class TrashRunQuitGuard {
    private let viewModel: AdaptiveExperienceViewModel
    private let confirmStop: @MainActor () -> Bool
    private let reply: @MainActor (Bool) -> Void
    /// A confirmed quit waiting for the run to end.
    private var pendingQuit: AnyCancellable?

    init(
        viewModel: AdaptiveExperienceViewModel,
        confirmStop: @escaping @MainActor () -> Bool = TrashRunQuitGuard.askToStop,
        reply: @escaping @MainActor (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    ) {
        self.viewModel = viewModel
        self.confirmStop = confirmStop
        self.reply = reply
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        guard viewModel.isExecuting else { return .terminateNow }
        // The quit already confirmed will reply when the run ends.
        guard pendingQuit == nil else { return .terminateCancel }
        guard confirmStop() else { return .terminateCancel }
        viewModel.dispatch(.cancel)
        // ponytail: waits for the whole run, including the refresh after it; reply at the receipt
        // write instead if that refresh ever makes quitting feel slow.
        pendingQuit = viewModel.$isExecuting
            .first { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pendingQuit = nil
                    self?.reply(true)
                }
            }
        return .terminateLater
    }

    static func askToStop() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("adaptive.quit.title")
        alert.informativeText = L("adaptive.quit.message")
        alert.addButton(withTitle: L("adaptive.quit.stop"))
        alert.addButton(withTitle: L("adaptive.quit.keep")).keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
