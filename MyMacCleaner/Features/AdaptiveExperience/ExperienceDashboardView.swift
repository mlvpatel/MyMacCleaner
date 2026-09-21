import SwiftUI
import CleanerCore

struct ExperienceDashboardView: View {
    @ObservedObject var viewModel: AdaptiveExperienceViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if let failure = viewModel.failure {
                    AdaptiveFailureBanner(failure: failure) {
                        viewModel.dispatch(.dismissFailure)
                    }
                }
                section(titleKey: "adaptive.section.opportunities", identifier: "adaptive.section.opportunities") {
                    opportunityCards
                }
                warningBanner
                section(titleKey: "adaptive.section.protected", identifier: "adaptive.section.protected-data") {
                    ProtectedDataNotice(
                        titleKey: "adaptive.protected.title",
                        messageKey: "adaptive.protected.body"
                    )
                    developerInventory
                }
                section(titleKey: "adaptive.section.memory", identifier: "adaptive.section.memory") {
                    memoryCard
                }
                section(titleKey: "adaptive.section.coverage", identifier: "adaptive.section.coverage") {
                    coverageCard
                }
                section(titleKey: "adaptive.section.history", identifier: "adaptive.section.history") {
                    historyCard
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.pageTopPadding)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .accessibilityIdentifier("adaptive.dashboard.scroll")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L("adaptive.dashboard.title"))
                .font(Theme.Typography.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("adaptive.dashboard.title")
            if viewModel.isRefreshing {
                ProgressView()
                    .accessibilityLabel(L("adaptive.dashboard.refreshing"))
                    .accessibilityIdentifier("adaptive.scan.progress")
            }
            Text(viewModel.snapshot?.explanationKeys.first.map { L($0) } ?? L("adaptive.dashboard.empty"))
                .foregroundStyle(.secondary)
        }
    }

    private var opportunityCards: some View {
        let identities = viewModel.snapshot?.authority.evidenceIdentities ?? []
        return Group {
            if identities.isEmpty {
                Text(L("adaptive.opportunities.empty"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("adaptive.opportunities.empty")
            } else {
                ForEach(identities, id: \.self) { identity in
                    Button {
                        viewModel.dispatch(.focus(opaqueID: identity))
                        viewModel.presentReview()
                    } label: {
                        TrustStateCard(
                            title: L("adaptive.opportunity.title"),
                            detail: identity,
                            identifier: "adaptive.card.\(identity)"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L("adaptive.opportunity.open.hint"))
                }
            }
        }
    }

    @ViewBuilder
    private var warningBanner: some View {
        if let snapshot = viewModel.snapshot {
            ForEach(warningKinds(from: snapshot), id: \.self) { kind in
                Text(L("adaptive.warning.\(kind)"))
                    .font(Theme.Typography.subheadline)
                    .accessibilityIdentifier("adaptive.warning.\(kind)")
            }
        }
    }

    private var developerInventory: some View {
        let facts = viewModel.source?.developerInventory ?? []
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            DeveloperCapabilityCard(facts: facts.isEmpty
                ? [L("adaptive.developer.none")]
                : facts.map { L($0.presenceKey) })
            ForEach(facts, id: \.opaqueID) { fact in
                Text(L(fact.protectionKey))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("developer.card.\(fact.opaqueID).protected")
            }
        }
    }

    private var memoryCard: some View {
        let outcome = viewModel.snapshot?.authority.memoryOutcome
        let key: String
        switch outcome {
        case .complete: key = "adaptive.memory.complete"
        case .partial: key = "adaptive.memory.partial"
        case .cancelled: key = "adaptive.memory.cancelled"
        case .unavailable: key = "adaptive.memory.unavailable"
        case .none: key = "adaptive.memory.none"
        }
        return TrustStateCard(
            title: L("adaptive.section.memory"),
            detail: L(key),
            identifier: "adaptive.memory.card"
        )
    }

    private var coverageCard: some View {
        let gaps = viewModel.snapshot?.authority.permissionGaps ?? []
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if gaps.isEmpty {
                Text(L("adaptive.coverage.none"))
                    .accessibilityIdentifier("adaptive.coverage.none")
            } else {
                ForEach(gaps, id: \.self) { gap in
                    Button {
                        viewModel.dispatch(.permissionHelp)
                    } label: {
                        Text(L("adaptive.coverage.\(gap.rawValue)"))
                    }
                    .accessibilityIdentifier("adaptive.coverage.\(gap.rawValue)")
                }
            }
        }
    }

    private var historyCard: some View {
        Button {
            viewModel.presentReceipts()
        } label: {
            TrustStateCard(
                title: L("adaptive.section.history"),
                detail: L("adaptive.history.open"),
                identifier: "adaptive.history.card"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("adaptive.history.open")
        .accessibilityHint(L("adaptive.history.open.hint"))
    }

    private func section<Content: View>(
        titleKey: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L(titleKey))
                .font(Theme.Typography.title3)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            content()
        }
    }

    private func warningKinds(from snapshot: AdaptiveExperienceProjection) -> [String] {
        var kinds: [String] = []
        if snapshot.authority.permissionGaps.isEmpty == false {
            kinds.append("permission")
        }
        if snapshot.authority.boundarySummaries.contains(where: { $0.externalVolume == .observedTrue }) {
            kinds.append("external-volume")
        }
        switch snapshot.authority.approvalValidity {
        case .invalid(.evidenceChanged),
             .invalid(.planDigestChanged),
             .invalid(.contextChanged),
             .invalid(.sessionChanged),
             .invalid(.expired):
            kinds.append("changed-evidence")
        default:
            break
        }
        switch snapshot.authority.scanState {
        case .unsupportedLayout:
            kinds.append("unknown-layout")
        default:
            break
        }
        return kinds
    }
}
