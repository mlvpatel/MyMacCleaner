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
            let unrecorded = viewModel.unrecordedMoveLocations
            if !unrecorded.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(L("adaptive.receipts.unrecorded"))
                    ForEach(Array(unrecorded.enumerated()), id: \.offset) { _, location in
                        Text(location)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("adaptive.receipts.unrecorded")
            }
            let rows = viewModel.snapshot?.authority.receipts ?? []
            if let failure = viewModel.receiptHistoryFailure {
                Text(L(failure.receiptsUnavailableKey))
                    .accessibilityIdentifier("adaptive.receipts.unavailable")
            } else if rows.isEmpty {
                Text(L("adaptive.receipts.empty"))
                    .accessibilityIdentifier("adaptive.receipts.empty")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(rows, id: \.id) { row in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                TrustStateCard(
                                    title: LFormat("adaptive.receipts.item", Self.dateText(row.createdAtUnixNanoseconds)),
                                    detail: L(row.statusMarker) + " · " + LFormat("adaptive.receipts.itemCount", row.itemCount),
                                    identifier: "adaptive.receipt.\(row.id)"
                                )
                                Text(L(row.recoveryMarker))
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("adaptive.recovery.\(row.id)")
                            }
                        }
                    }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive.receipts")
    }

    private static func dateText(_ unixNanoseconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(unixNanoseconds) / 1_000_000_000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}
