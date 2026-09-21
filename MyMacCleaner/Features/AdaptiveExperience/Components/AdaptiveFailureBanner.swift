import SwiftUI

/// Explains why evidence could not be shown or a run did not start. Never offers a retry that bypasses review.
struct AdaptiveFailureBanner: View {
    let failure: AdaptiveSessionFailure
    let onDismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(L(failure.messageKey))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("adaptive.failure.message")
            Button(L("adaptive.failure.dismiss"), action: onDismiss)
                .accessibilityIdentifier("adaptive.failure.dismiss")
        }
        .padding(Theme.Spacing.md)
        .background(
            Color.orange.opacity(contrast == .increased ? 0.28 : 0.12),
            in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive.failure")
    }
}
