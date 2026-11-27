import SwiftUI

/// Says why the last scan failed, so a failed scan never looks like an empty or unscanned page.
struct ScanErrorNotice: View {
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.sm)
        .glassCard(tint: .orange, cornerRadius: Theme.CornerRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan.error")
    }
}
