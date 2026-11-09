import SwiftUI

/// Says the last scan stopped because you left its page, so an empty page never looks like a
/// finished scan.
struct ScanStoppedNotice: View {
    var body: some View {
        Label(L("scan.stoppedOnLeave"), systemImage: "pause.circle")
            .font(Theme.Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scan.stopped-on-leave")
    }
}
