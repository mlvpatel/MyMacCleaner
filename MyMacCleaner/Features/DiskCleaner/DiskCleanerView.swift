import SwiftUI

struct DiskCleanerView: View {
    @ObservedObject var viewModel: DiskCleanerViewModel
    @ObservedObject var spaceLensViewModel: SpaceLensViewModel
    /// Owned by AppState, like the other view models, so its results survive a section switch.
    @ObservedObject var privacyViewModel: BrowserPrivacyViewModel
    let openExperience: () -> Void
    /// "Learn why" on the Trash notice: Experience on its Trash explanation, without a scan.
    let openTrashExplanation: () -> Void
    let openPermissions: () -> Void
    @State private var isVisible = false

    // Section color for disk cleaner
    private let sectionColor = Theme.Colors.storage

    enum DiskCleanerTab: String, CaseIterable {
        case cleaner
        case privacy
        case spaceLens

        var icon: String {
            switch self {
            case .cleaner: return "internaldrive"
            case .privacy: return "hand.raised.fill"
            case .spaceLens: return "circle.hexagongrid.fill"
            }
        }

        var localizedName: String {
            switch self {
            case .cleaner: return L("diskCleaner.tab.cleaner")
            case .privacy: return L("diskCleaner.tab.privacy")
            case .spaceLens: return L("diskCleaner.tab.spaceLens")
            }
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    headerSection
                        .staggeredAnimation(index: 0, isActive: isVisible)
                    if viewModel.scanStoppedByLeaving {
                        ScanStoppedNotice()
                    }

                    // Tab picker
                    tabPicker
                        .staggeredAnimation(index: 1, isActive: isVisible)

                    // Content based on selected tab
                    switch viewModel.selectedTab {
                    case .cleaner:
                        cleanerContent
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    case .privacy:
                        BrowserPrivacyView(
                            viewModel: privacyViewModel,
                            openExperience: openExperience,
                            openPermissions: openPermissions
                        )
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    case .spaceLens:
                        SpaceLensView(viewModel: spaceLensViewModel, openExperience: openExperience)
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.pageTopPadding)
            }

            // Scanning overlay
            if viewModel.isScanning {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)

                ScanningOverlay(
                    progress: nil,
                    category: L("scan.inProgress.caption"),
                    accentColor: sectionColor,
                    onCancel: viewModel.cancelScan
                )
                .motionTransition(.scale.combined(with: .opacity))
            }

            ToastOverlay(presenter: viewModel.toasts, onLearnWhy: openTrashExplanation)
        }
        .animation(Theme.Animation.spring, value: viewModel.selectedTab)
        .animation(Theme.Animation.springSmooth, value: viewModel.isScanning)
        .sheet(item: $viewModel.detailCategory) { _ in
            if let result = viewModel.detailResult {
                CategoryDetailSheet(
                    result: result,
                    onClose: { viewModel.detailCategory = nil }
                )
            }
        }
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
        }
        .onDisappear {
            viewModel.leavePage()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("navigation.diskCleaner"))
                    .font(Theme.Typography.size28Bold)

                Text(L("diskCleaner.subtitle"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.hasScanned && !viewModel.scanResults.isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text(viewModel.formattedTotalSize)
                            .font(Theme.Typography.size22Semibold)
                            .foregroundStyle(sectionColor)

                        Text(LFormat("diskCleaner.itemsFound %lld", viewModel.totalItemCount))
                            .font(Theme.Typography.size11)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: Theme.CornerRadius.medium)
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack {
            GlassTabPicker(
                tabs: DiskCleanerTab.allCases,
                selection: $viewModel.selectedTab,
                icon: { $0.icon },
                label: { $0.localizedName },
                accentColor: sectionColor
            )

            Spacer()
        }
    }

    // MARK: - Cleaner Content

    @ViewBuilder
    private var cleanerContent: some View {
        if let error = viewModel.errorMessage {
            ScanErrorNotice(message: error)
        }

        if let coverage = viewModel.lastScanCoverage, !coverage.isComplete {
            ScanCoverageNotice(coverage: coverage, openPermissions: openPermissions)
        }

        if !viewModel.hasScanned {
            // Initial scan prompt
            scanPromptSection
        } else if viewModel.scanResults.isEmpty {
            emptyStateSection
        } else {
            // Category list
            categoryListSection

            ExperienceHandoffCard(openExperience: openExperience)
        }

        // Trash inventory card
        trashInventorySection
            .staggeredAnimation(index: 3, isActive: isVisible)
    }

    // MARK: - Scan Prompt

    private var scanPromptSection: some View {
        VStack(spacing: Theme.Spacing.section) {
            // Icon
            ZStack {
                Circle()
                    .fill(sectionColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Circle()
                                .strokeBorder(sectionColor.opacity(0.3), lineWidth: 1)
                        }

                    Image(systemName: "internaldrive.fill")
                        .font(Theme.Typography.size32Medium)
                        .foregroundStyle(sectionColor.gradient)
                }
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("diskCleaner.scan.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("diskCleaner.scan.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            GlassActionButton(
                L("diskCleaner.scan.startButton"),
                icon: "magnifyingglass",
                color: sectionColor
            ) {
                viewModel.startScan()
            }
            .accessibilityIdentifier("diskCleaner.scan.start")

            // Home's notice, said before the scan starts, so the macOS folder prompts are expected.
            if !viewModel.hasFullDiskAccess {
                Text(L("permissions.fda.limitedScan.folders"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "tray")
                .font(Theme.Typography.size48)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("scan.empty.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L(viewModel.lastScanCoverage?.isComplete == false ? "scan.empty.incomplete" : "scan.empty.complete"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: viewModel.startScan) {
                Text(L("diskCleaner.scanAgain"))
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(sectionColor)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Category List

    private var categoryListSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text(L("diskCleaner.categories"))
                    .font(Theme.Typography.headline)

                Spacer()

                Button(action: viewModel.startScan) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "arrow.clockwise")
                        Text(L("diskCleaner.rescan"))
                    }
                    .font(Theme.Typography.size12Medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxxs)
                    .glassCard(cornerRadius: Theme.CornerRadius.small)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }

            // Category cards
            ForEach(viewModel.scanResults) { result in
                CleanupCategoryCard(
                    result: result,
                    isExpanded: viewModel.expandedCategory == result.category,
                    onToggleExpand: {
                        viewModel.toggleCategoryExpansion(result.category)
                    },
                    onViewDetails: {
                        viewModel.showDetails(for: result.category)
                    }
                )
            }
        }
    }

    // MARK: - Trash Inventory Section

    private var trashInventoryText: String {
        switch viewModel.trashInventory {
        case .unknown:
            return L("safety.notice.trashMeasuring")
        case .unavailable:
            return L("safety.notice.trashSizeUnavailable")
        case .measured(let bytes) where bytes > 0:
            return LFormat(
                "safety.notice.trashSize %@",
                ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            )
        case .measured:
            return L("safety.notice.trashNoItems")
        }
    }

    private var trashInventorySection: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: "info.circle.fill")
                    .font(Theme.Typography.size20Medium)
                    .foregroundStyle(Color.blue.gradient)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("safety.notice.trashReview.action"))
                    .font(Theme.Typography.subheadline.weight(.semibold))

                Text(trashInventoryText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: viewModel.explainTrashSafety) {
                HStack(spacing: Theme.Spacing.xxxs) {
                    Image(systemName: "info.circle")
                        .font(Theme.Typography.size12Medium)
                    Text(L("safety.notice.action.learnWhy"))
                        .font(Theme.Typography.size13Medium)
                }
                .foregroundStyle(Color.blue)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .glassCard()
        .onAppear {
            viewModel.refreshTrashSize()
        }
    }
}

// MARK: - Scanning Overlay

struct ScanningOverlay: View {
    /// nil when the scan cannot measure progress: an indeterminate spinner, never a fake percentage.
    let progress: Double?
    let category: String
    var accentColor: Color = .blue
    var onCancel: (() -> Void)? = nil

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)

                if let progress {
                    Circle()
                        .stroke(Theme.Colors.track, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            accentColor.gradient,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(Theme.Animation.spring, value: progress)

                    Image(systemName: "magnifyingglass")
                        .font(Theme.Typography.size28Medium)
                        .foregroundStyle(accentColor)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(accentColor)
                }
            }

            VStack(spacing: Theme.Spacing.xxs) {
                Text(L("common.scanning"))
                    .font(Theme.Typography.size20Semibold)

                Text(category)
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let progress {
                    Text("\(Int(progress * 100))%")
                        .font(Theme.Typography.size24Bold.monospacedDigit())
                        .foregroundStyle(accentColor)
                }
            }

            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                            .fill(Theme.Colors.track)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                            .fill(accentColor.gradient)
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(Theme.Animation.spring, value: progress)
                    }
                }
                .frame(width: 200, height: 8)
            }

            // Cancel button (optional)
            if let onCancel = onCancel {
                Button(action: onCancel) {
                    Text(L("common.cancel"))
                        .font(Theme.Typography.size14Medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.surfaceHover)
                        .cornerRadius(Theme.CornerRadius.small)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 280)
        .glassCardProminent()
        .onAppear {
            // No perpetual pulse with Reduce Motion.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DiskCleanerView(
        viewModel: DiskCleanerViewModel(),
        spaceLensViewModel: SpaceLensViewModel(),
        privacyViewModel: BrowserPrivacyViewModel(),
        openExperience: {},
        openTrashExplanation: {},
        openPermissions: {}
    )
        .frame(width: 800, height: 600)
}
