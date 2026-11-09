import Foundation
import Testing
@testable import MyMacCleaner

@Suite("Toast Presenter")
@MainActor
struct ToastPresenterTests {
    private actor DelayLog {
        private(set) var delays: [UInt64] = []
        func record(_ delay: UInt64) { delays.append(delay) }
    }

    private final class AnnouncementLog {
        var items: [String] = []
    }

    @Test("Success and info toasts hide after the toast duration")
    func successAndInfoAutoHide() async {
        for type in [ToastType.success, .info] {
            let log = DelayLog()
            let presenter = ToastPresenter(sleep: { await log.record($0) }, announce: { _ in })

            presenter.show("Done", type: type)
            #expect(presenter.current?.message == "Done")
            await presenter.hideTask?.value

            #expect(presenter.current == nil)
            #expect(await log.delays == [Theme.Timing.toastDuration])
        }
    }

    @Test("Errors stay until dismissed")
    func errorsStay() {
        let presenter = ToastPresenter(announce: { _ in })

        presenter.show("Scan failed", type: .error)

        #expect(presenter.hideTask == nil)
        #expect(presenter.current?.type == .error)
        presenter.dismiss()
        #expect(presenter.current == nil)
    }

    @Test("Safety notices stay until dismissed and keep their typed notice")
    func safetyNoticesStay() {
        let presenter = ToastPresenter(announce: { _ in })
        let notice = SafetyNoticePresenter().homeTrashReviewNotice()

        presenter.show(notice)

        #expect(presenter.hideTask == nil)
        #expect(presenter.current?.safetyNotice == notice)
        #expect(presenter.current?.type == .info)
        presenter.dismiss()
        #expect(presenter.current == nil)
    }

    @Test("An older timer never hides a newer toast")
    func olderTimerKeepsNewerToast() throws {
        let presenter = ToastPresenter(announce: { _ in })
        presenter.show("First", type: .success)
        let first = presenter.current?.id

        presenter.show("Second", type: .error)
        presenter.expire(try #require(first))

        #expect(presenter.current?.message == "Second")
    }

    @Test("Every toast is announced to VoiceOver")
    func everyToastIsAnnounced() {
        let log = AnnouncementLog()
        let presenter = ToastPresenter(announce: { log.items.append($0) })
        let notice = SafetyNoticePresenter().homeTrashReviewNotice()

        presenter.show("Saved", type: .success)
        presenter.show(notice)

        #expect(log.items == ["Saved", "\(notice.title). \(notice.message)"])
    }
}
