import AppKit
import SwiftUI
import CleanerCore

struct ExperienceDashboardView: View {
    @ObservedObject var viewModel: AdaptiveExperienceViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if let failure = viewModel.failure {
                    AdaptiveFailureBanner(failure: failure, onOpenReceipts: viewModel.presentReceipts) {
                        viewModel.dispatch(.dismissFailure)
                    }
                }
                section(titleKey: "adaptive.section.opportunities", identifier: "adaptive.section.opportunities") {
                    // "Learn why" on the Home and Disk Cleaner Trash notices lands here.
                    Text(L("adaptive.trash.why"))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("adaptive.trash.why")
                    opportunityCards
                }
                warningBanner
                section(titleKey: "adaptive.section.protected", identifier: "adaptive.section.protected-data") {
                    ProtectedDataNotice(
                        titleKey: "adaptive.protected.title",
                        messageKey: "adaptive.protected.body"
                    )
                    developerInventory
                    modelInventory
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
            AdaptiveRunStatus(
                isExecuting: viewModel.isExecuting,
                summary: viewModel.lastRunSummary,
                identifier: "adaptive.dashboard.execution"
            ) {
                viewModel.presentReceipts()
            }
            Text(viewModel.snapshot?.explanationKeys.first.map { L($0) } ?? L("adaptive.dashboard.empty"))
                .foregroundStyle(.secondary)
        }
    }

    /// Only the plan's items are cards; findings outside the plan collapse into one count.
    private var opportunityCards: some View {
        let authority = viewModel.snapshot?.authority
        let items = authority?.planItems ?? []
        let reviewOnly = authority?.reviewOnlyFindingCount ?? 0
        return Group {
            if let authority, !items.isEmpty {
                Text(AdaptivePlanText.total(itemCount: items.count, bytes: authority.expectedConservativeBytes))
                    .font(Theme.Typography.subheadline)
                    .accessibilityIdentifier("adaptive.plan.total")
                let (shown, hidden) = AdaptiveListLimit.split(items)
                ForEach(shown, id: \.identity) { item in
                    TrustStateCardButton(
                        title: item.name,
                        detail: AdaptivePlanText.detail(item),
                        identifier: "adaptive.card.\(item.identity)"
                    ) {
                        viewModel.dispatch(.focus(opaqueID: item.identity))
                        viewModel.presentReview()
                    }
                    .accessibilityHint(L("adaptive.opportunity.open.hint"))
                }
                if hidden > 0 {
                    Text(LFormat("adaptive.opportunities.more", hidden))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("adaptive.opportunities.more")
                }
            } else {
                Text(L("adaptive.opportunities.empty"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("adaptive.opportunities.empty")
            }
            if reviewOnly > 0 {
                Text(LFormat("adaptive.opportunities.reviewOnly", reviewOnly))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("adaptive.opportunities.reviewOnly")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(fact.protectionKey))
                        .accessibilityIdentifier("developer.card.\(fact.opaqueID).protected")
                    if let bytes = fact.sizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                            .accessibilityIdentifier("developer.card.\(fact.opaqueID).size")
                    }
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var modelInventory: some View {
        let defaultStores = viewModel.source?.modelInventory ?? []
        let selectedStores = viewModel.selectedModelStores
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L("adaptive.modelInventory.title"))
                .font(Theme.Typography.subheadline)
                .accessibilityIdentifier("adaptive.modelInventory")
            ForEach(Array(defaultStores.enumerated()), id: \.offset) { index, store in
                modelStoreRow(store, index: index)
            }
            ForEach(Array(selectedStores.enumerated()), id: \.offset) { index, store in
                modelStoreRow(store, index: 1_000 + index)
            }
            ForEach(viewModel.environmentModelPrompts, id: \.self) { name in
                Text("\(name): \(L("adaptive.modelInventory.envPrompt"))")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("adaptive.modelInventory.envPrompt.\(name)")
            }
            GlassActionButton(
                L("adaptive.modelInventory.addRoot"),
                icon: "folder.badge.plus",
                color: NavigationSection.adaptiveExperience.color,
                action: selectModelFolder
            )
            .accessibilityIdentifier("adaptive.modelInventory.addRoot")
        }
    }

    private func selectModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("adaptive.modelInventory.addRoot")
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addSelectedModelRoot(url)
        }
    }

    @ViewBuilder
    private func modelStoreRow(_ store: ModelStoreProjection, index: Int) -> some View {
        let accounting = store.accounting
        VStack(alignment: .leading, spacing: 2) {
            Text(L(storeLabelKey(for: store)))
                .font(Theme.Typography.subheadline)
                .accessibilityIdentifier("adaptive.modelInventory.store.\(index)")
            Text("\(L("adaptive.modelInventory.logical")): \(formattedBytes(accounting.logicalReferencedBytes))")
            Text("\(L("adaptive.modelInventory.unique")): \(formattedBytes(accounting.uniquePhysicalBytes))")
            Text("\(L("adaptive.modelInventory.shared")): \(formattedBytes(accounting.sharedBytesIncludedInUniquePhysical))")
            Text("\(L("adaptive.modelInventory.incomplete")): \(formattedBytes(accounting.locallyObservedIncompleteBytes))")
        }
        .font(Theme.Typography.subheadline)
        .foregroundStyle(.secondary)
    }

    private func storeLabelKey(for store: ModelStoreProjection) -> String {
        switch store.entries.first?.layout {
        case .huggingFaceCacheV1?:
            return "adaptive.modelInventory.huggingface"
        case .ollamaV1?:
            return "adaptive.modelInventory.ollama"
        case .selectedRootV1?:
            return "adaptive.modelInventory.selected"
        case nil:
            return "adaptive.modelInventory.title"
        }
    }

    private func formattedBytes(_ value: EvidenceValue<Int>) -> String {
        switch value {
        case .observed(let bytes):
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        case .unknown, .unavailable:
            return L("adaptive.modelInventory.unavailable")
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
        TrustStateCardButton(
            title: L("adaptive.section.history"),
            detail: L("adaptive.history.open"),
            identifier: "adaptive.history.card",
            action: viewModel.presentReceipts
        )
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

/// Large scans yield tens of thousands of findings; a row for each stalls SwiftUI and the
/// accessibility tree, so evidence lists render a bounded prefix and summarize the rest.
enum AdaptiveListLimit {
    static let rows = 50

    static func split<Item>(_ items: [Item], limit: Int = rows) -> (shown: [Item], hidden: Int) {
        (Array(items.prefix(limit)), max(0, items.count - limit))
    }
}

/// Plain-language plan text shared by the dashboard, the review sheet and the confirmation.
enum AdaptivePlanText {
    /// The confirmation names at most this many items, then counts the rest.
    static let confirmationNameLimit = 10

    static func bytes(_ total: AdaptiveByteTotal) -> String {
        switch total {
        case .observed(let bytes):
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        case .unavailable, .overflowing:
            return L("adaptive.plan.size.unavailable")
        }
    }

    static func total(itemCount: Int, bytes total: AdaptiveByteTotal) -> String {
        LFormat("adaptive.plan.total", itemCount, bytes(total))
    }

    /// Parent folder, conservative size and recovery path, e.g. "In com.example · 12 KB · Rebuildable".
    static func detail(_ item: AdaptivePlanItem) -> String {
        [
            item.parentName.map { LFormat("adaptive.plan.item.parent", $0) },
            ByteCountFormatter.string(fromByteCount: item.conservativeBytes, countStyle: .file),
            L("adaptive.review.recovery.\(item.recoveryPath.rawValue)")
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    static func approvalTitle(itemCount: Int, total: AdaptiveByteTotal) -> String {
        itemCount == 1
            ? LFormat("adaptive.approval.title.one", bytes(total))
            : LFormat("adaptive.approval.title", itemCount, bytes(total))
    }

    static func approvalMessage(names: [String]) -> String {
        let (shown, hidden) = AdaptiveListLimit.split(names, limit: confirmationNameLimit)
        let more = hidden > 0 ? [LFormat("adaptive.opportunities.more", hidden)] : []
        return (shown + more + [L("adaptive.approval.message")]).joined(separator: "\n")
    }
}
