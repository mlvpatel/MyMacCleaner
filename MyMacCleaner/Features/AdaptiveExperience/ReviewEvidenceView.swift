import SwiftUI
import CleanerCore

struct ReviewEvidenceView: View {
    @ObservedObject var viewModel: AdaptiveExperienceViewModel

    var body: some View {
        // Redraws when the plan's lifetime ends, so Approve gives way to Refresh while the sheet is open.
        TimelineView(.explicit(expiryRedrawDates)) { _ in
            content
        }
        .confirmationDialog(
            approvalTitle,
            isPresented: approvalConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L("adaptive.approval.confirm"), role: .destructive) {
                viewModel.dispatch(.confirmApproveDisplayedPlan)
            }
            .accessibilityIdentifier("adaptive.approval.confirm")
        } message: {
            Text(AdaptivePlanText.approvalMessage(names: viewModel.snapshot?.authority.planItems.map(\.name) ?? []))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("adaptive.review.title"))
                .font(Theme.Typography.title2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("adaptive.review.title")
            if let failure = viewModel.failure {
                AdaptiveFailureBanner(failure: failure, onOpenReceipts: viewModel.presentReceipts) {
                    viewModel.dispatch(.dismissFailure)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if let snapshot = viewModel.snapshot {
                            evidence(snapshot)
                        } else {
                            Text(L("adaptive.review.empty"))
                                .accessibilityIdentifier("adaptive.review.empty")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    // A dashboard card opens review on its own item.
                    if let focused = viewModel.focusedID {
                        proxy.scrollTo(focused, anchor: .center)
                    }
                }
            }
            AdaptiveRunStatus(
                isExecuting: viewModel.isExecuting,
                summary: viewModel.lastRunSummary,
                identifier: "adaptive.execution"
            ) {
                viewModel.presentReceipts()
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
            } else {
                // An expired, changed or missing plan cannot be approved; a refresh builds a new one here.
                Button(L("adaptive.refresh")) {
                    viewModel.dispatch(.refresh)
                }
                .accessibilityIdentifier("adaptive.review.refresh")
                .accessibilityHint(L("adaptive.refresh.hint"))
                .disabled(viewModel.isRefreshing)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 520, minHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive.review")
    }

    /// The plan's expiry, and a second later in case the first redraw lands a hair early.
    private var expiryRedrawDates: [Date] {
        guard let nanoseconds = viewModel.snapshot?.authority.planExpiresAtNanoseconds else { return [] }
        let expiry = Date(timeIntervalSince1970: TimeInterval(nanoseconds) / 1_000_000_000)
        return [expiry, expiry.addingTimeInterval(1)]
    }

    /// Names what will move and how much, e.g. "Move 3 items (12.4 MB) to the Trash?".
    private var approvalTitle: String {
        guard let authority = viewModel.snapshot?.authority else { return L("adaptive.approval.button") }
        return AdaptivePlanText.approvalTitle(
            itemCount: authority.planItems.count,
            total: authority.expectedConservativeBytes
        )
    }

    @ViewBuilder
    private func evidence(_ snapshot: AdaptiveExperienceProjection) -> some View {
        let authority = snapshot.authority
        let isTechnical = snapshot.disclosureDepth == .technical
        validityBanner(viewModel.isPlanExpired ? .invalid(.expired) : authority.approvalValidity)
        ForEach(snapshot.explanationKeys + snapshot.groupingKeys + snapshot.detailRowKeys, id: \.self) { key in
            Text(L(key))
                .accessibilityIdentifier("adaptive.review.key")
        }
        if !authority.planItems.isEmpty {
            Text(AdaptivePlanText.total(itemCount: authority.planItems.count, bytes: authority.expectedConservativeBytes))
                .font(Theme.Typography.headline)
                .accessibilityIdentifier("adaptive.review.plan.total")
            let (shown, hidden) = AdaptiveListLimit.split(authority.planItems)
            ForEach(shown, id: \.identity) { item in
                planRow(item, showsIdentity: isTechnical)
                    .id(item.identity)
            }
            if hidden > 0 {
                Text(LFormat("adaptive.opportunities.more", hidden))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("adaptive.review.plan.more")
            }
        }
        if authority.reviewOnlyFindingCount > 0 {
            Text(LFormat("adaptive.opportunities.reviewOnly", authority.reviewOnlyFindingCount))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("adaptive.review.reviewOnly")
        }
        // Opaque evidence identities are Technical detail only; elsewhere they read as noise.
        if isTechnical {
            let (shown, hidden) = AdaptiveListLimit.split(authority.evidenceIdentities)
            ForEach(shown, id: \.self) { identity in
                Text(identity)
                    .font(Theme.Typography.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("adaptive.review.item.\(identity)")
            }
            if hidden > 0 {
                Text(LFormat("adaptive.opportunities.more", hidden))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("adaptive.review.more")
            }
        }
    }

    private func planRow(_ item: AdaptivePlanItem, showsIdentity: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(item.name)
                .font(Theme.Typography.headline)
            Text(AdaptivePlanText.detail(item))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
            if showsIdentity {
                Text(item.identity)
                    .font(Theme.Typography.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            item.identity == viewModel.focusedID ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("adaptive.review.plan.\(item.identity)")
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
