import SwiftUI

/// State of the one file-moving flow: a labelled progress view while items move to the Trash,
/// then a counted summary with a way to open the receipt.
struct AdaptiveRunStatus: View {
    let isExecuting: Bool
    let summary: AdaptiveRunSummary?
    /// Identifier prefix, so the dashboard and review sheet copies stay distinct.
    let identifier: String
    let onViewReceipt: () -> Void

    var body: some View {
        if isExecuting {
            ProgressView(L("adaptive.execution.progress"))
                .controlSize(.small)
                .accessibilityIdentifier("\(identifier).progress")
        } else if let summary {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text(summary.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("\(identifier).summary")
                Button(L("adaptive.execution.viewReceipt"), action: onViewReceipt)
                    .accessibilityIdentifier("\(identifier).viewReceipt")
                    .accessibilityHint(L("adaptive.execution.viewReceipt.hint"))
            }
            .padding(Theme.Spacing.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .accessibilityElement(children: .contain)
        }
    }
}
