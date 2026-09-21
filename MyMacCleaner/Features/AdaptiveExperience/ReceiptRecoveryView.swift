import SwiftUI
import CleanerCore

struct ReceiptRecoveryView: View {
    @ObservedObject var viewModel: AdaptiveExperienceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("adaptive.receipts.title"))
                .font(Theme.Typography.title2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("adaptive.receipts.title")
            let ids = viewModel.snapshot?.authority.receiptIDs ?? []
            if ids.isEmpty {
                Text(L("adaptive.receipts.empty"))
                    .accessibilityIdentifier("adaptive.receipts.empty")
            } else {
                ForEach(ids, id: \.self) { id in
                    TrustStateCard(
                        title: L("adaptive.receipts.item"),
                        detail: id,
                        identifier: "adaptive.receipt.\(id)"
                    )
                }
                ForEach(Array((viewModel.snapshot?.authority.receiptRecoveryMarkers ?? []).enumerated()), id: \.offset) { index, marker in
                    Text(L(marker))
                        .accessibilityIdentifier("adaptive.recovery.\(ids.indices.contains(index) ? ids[index] : "marker")")
                }
            }
            Button(L("adaptive.receipts.close")) {
                viewModel.dismissSheet()
            }
            .accessibilityIdentifier("adaptive.receipts.close")
            .accessibilityHint(L("adaptive.receipts.close.hint"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 520, minHeight: 360)
        .accessibilityIdentifier("adaptive.receipts")
    }
}
