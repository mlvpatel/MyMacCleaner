import SwiftUI

/// One toast at a time for a screen. Success and info toasts hide after
/// `Theme.Timing.toastDuration`; errors and safety notices stay until dismissed, so text the user
/// has to read never times out. Every toast is announced to VoiceOver.
@MainActor
final class ToastPresenter: ObservableObject {
    struct Toast {
        let id = UUID()
        let message: String
        let type: ToastType
        let safetyNotice: SafetyNoticeState?
    }

    @Published private(set) var current: Toast?
    /// Readable so tests can await the auto-hide instead of sleeping.
    private(set) var hideTask: Task<Void, Never>?

    private let sleep: @Sendable (UInt64) async throws -> Void
    private let announce: @MainActor (String) -> Void

    init(
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.sleep = sleep
        self.announce = announce
    }

    func show(_ message: String, type: ToastType) {
        present(Toast(message: message, type: type, safetyNotice: nil))
    }

    func show(_ notice: SafetyNoticeState) {
        present(Toast(message: notice.message, type: .info, safetyNotice: notice))
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        current = nil
    }

    /// nil keeps the toast up until the user dismisses it.
    static func autoHideDelay(for toast: Toast) -> UInt64? {
        guard toast.safetyNotice == nil else { return nil }
        switch toast.type {
        case .success, .info: return Theme.Timing.toastDuration
        case .error: return nil
        }
    }

    /// Hides the toast only while it is still the one showing, so an older timer never cuts a
    /// newer toast short.
    func expire(_ id: UUID) {
        guard current?.id == id else { return }
        current = nil
    }

    private func present(_ toast: Toast) {
        hideTask?.cancel()
        hideTask = nil
        current = toast
        announce(toast.safetyNotice.map { "\($0.title). \($0.message)" } ?? toast.message)

        guard let delay = Self.autoHideDelay(for: toast) else { return }
        let id = toast.id
        hideTask = Task { [weak self, sleep] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            self?.expire(id)
        }
    }
}
