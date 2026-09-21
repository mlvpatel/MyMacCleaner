import SwiftUI
import CleanerCore

struct ReviewEvidenceView: View {
    @ObservedObject var viewModel: AdaptiveExperienceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("adaptive.review.title"))
                .font(Theme.Typography.title2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("adaptive.review.title")
            if let failure = viewModel.failure {
                AdaptiveFailureBanner(failure: failure) {
                    viewModel.dispatch(.dismissFailure)
                }
            }
            if let snapshot = viewModel.snapshot {
                validityBanner(snapshot.authority.approvalValidity)
                ForEach(snapshot.explanationKeys + snapshot.groupingKeys + snapshot.detailRowKeys, id: \.self) { key in
                    Text(L(key))
                        .accessibilityIdentifier("adaptive.review.key")
                }
                ForEach(snapshot.authority.evidenceIdentities, id: \.self) { identity in
                    Text(identity)
                        .font(Theme.Typography.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("adaptive.review.item.\(identity)")
                }
                ForEach(snapshot.authority.recoveryPaths.map(\.rawValue), id: \.self) { path in
                    Text(L("adaptive.review.recovery.\(path)"))
                }
                ForEach(Array(snapshot.authority.executionOutcomes.enumerated()), id: \.offset) { _, outcome in
                    Text(L(outcomeKey(outcome)))
                        .accessibilityIdentifier("adaptive.execution.outcome")
                }
            } else {
                Text(L("adaptive.review.empty"))
                    .accessibilityIdentifier("adaptive.review.empty")
            }
            Button(L("adaptive.review.close")) {
                viewModel.dismissSheet()
            }
            .accessibilityIdentifier("adaptive.review.close")
            .accessibilityHint(L("adaptive.review.close.hint"))
            .keyboardShortcut(.cancelAction)
            if viewModel.isExecuting {
                Button(L("adaptive.execution.stop")) {
                    viewModel.dispatch(.cancel)
                }
                .accessibilityIdentifier("adaptive.execution.stop")
                .accessibilityHint(L("adaptive.execution.stop.hint"))
                .keyboardShortcut(".", modifiers: .command)
                .disabled(viewModel.isStopRequested)
            } else if viewModel.canRequestApproval {
                Button(L("adaptive.approval.button")) {
                    viewModel.dispatch(.requestApproveDisplayedPlan)
                }
                .accessibilityIdentifier("adaptive.approval.button")
                .accessibilityHint(L("adaptive.approval.button.hint"))
                .disabled(viewModel.isExecuting)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 520, minHeight: 360)
        .accessibilityIdentifier("adaptive.review")
        .confirmationDialog(
            L("adaptive.approval.title"),
            isPresented: approvalConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L("adaptive.approval.confirm"), role: .destructive) {
                viewModel.dispatch(.confirmApproveDisplayedPlan)
            }
            .accessibilityIdentifier("adaptive.approval.confirm")
        } message: {
            Text(L("adaptive.approval.message"))
        }
    }

    private var approvalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showApprovalConfirmation },
            set: { presented in
                if !presented {
                    viewModel.dispatch(.dismissApproveDisplayedPlan)
                }
            }
        )
    }

    private func outcomeKey(_ outcome: AdaptiveExecutionOutcomeKind) -> String {
        switch outcome {
        case .moved:
            return "adaptive.execution.moved"
        case .skippedStale:
            return "adaptive.execution.skippedStale"
        case .failed:
            return "adaptive.execution.failed"
        case .cancelled:
            return "adaptive.execution.cancelled"
        }
    }

    @ViewBuilder
    private func validityBanner(_ validity: ApprovalValidity) -> some View {
        switch validity {
        case .validForReview:
            Text(L("adaptive.review.valid"))
                .accessibilityIdentifier("adaptive.review.valid")
        case .invalid(let reason):
            Text(L("adaptive.review.invalid.\(reasonKey(reason))"))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("adaptive.approval.invalid")
        }
    }

    private func reasonKey(_ reason: ApprovalInvalidReason) -> String {
        switch reason {
        case .missingApproval: return "missingApproval"
        case .sessionChanged: return "sessionChanged"
        case .expired: return "expired"
        case .contextChanged: return "contextChanged"
        case .planDigestChanged: return "planDigestChanged"
        case .evidenceChanged: return "evidenceChanged"
        }
    }
}
