import SwiftUI

struct DiskCleanerView: View {
    @ObservedObject var viewModel: DiskCleanerViewModel
    @ObservedObject var spaceLensViewModel: SpaceLensViewModel
    @StateObject private var privacyViewModel = BrowserPrivacyViewModel()
    @State private var isVisible = false
    @State private var selectedTab: DiskCleanerTab = .cleaner

    // Section color for disk cleaner
    private let sectionColor = Theme.Colors.storage

    enum DiskCleanerTab: String, CaseIterable {
        case cleaner
        case privacy
        case spaceLens

        var icon: String {
            switch self {
            case .cleaner: return "trash"
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

                    // Tab picker
                    tabPicker
                        .staggeredAnimation(index: 1, isActive: isVisible)

                    // Content based on selected tab
                    switch selectedTab {
                    case .cleaner:
                        cleanerContent
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    case .privacy:
                        BrowserPrivacyView(viewModel: privacyViewModel)
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    case .spaceLens:
                        SpaceLensView(viewModel: spaceLensViewModel)
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
                    progress: viewModel.scanProgress,
                    category: viewModel.currentScanCategory?.localizedName ?? L("diskCleaner.scan.preparing"),
                    accentColor: sectionColor,
                    onCancel: viewModel.cancelScan
                )
                .transition(.scale.combined(with: .opacity))
            }

            // Toast
            if viewModel.showToast {
                VStack {
                    ToastView(
                        message: viewModel.toastMessage,
                        type: viewModel.toastType,
                        safetyNotice: viewModel.latestSafetyNotice,
                        onDismiss: viewModel.dismissToast
                    )
                    .padding(.top, Theme.Spacing.lg)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Animation.spring, value: selectedTab)
        .animation(Theme.Animation.springSmooth, value: viewModel.isScanning)
        .animation(Theme.Animation.spring, value: viewModel.showToast)
        .sheet(isPresented: $viewModel.showCategoryDetail) {
            if let category = viewModel.selectedCategory {
                CategoryDetailSheet(
                    result: category,
                    onToggleItem: { item in
                        viewModel.toggleItemSelection(item, in: category.category)
                    },
                    onClose: { viewModel.showCategoryDetail = false }
                )
            }
        }
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
        }
        .onDisappear {
            viewModel.cancelScan()
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
                selection: $selectedTab,
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
        if !viewModel.hasScanned {
            // Initial scan prompt
            scanPromptSection
        } else if viewModel.scanResults.isEmpty {
            // No junk found
            emptyStateSection
        } else {
            // Category list
            categoryListSection

            // Review notice button
            reviewButtonSection
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
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.size48)
                .foregroundStyle(.green)

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("diskCleaner.empty.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("diskCleaner.empty.description"))
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
            // Selection controls
            HStack {
                Text(L("diskCleaner.categories"))
                    .font(Theme.Typography.headline)

                Spacer()

                Button(L("diskCleaner.selectAll")) {
                    viewModel.selectAll()
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.size12Medium)
                .foregroundStyle(sectionColor)

                Text("·")
                    .foregroundStyle(.tertiary)

                Button(L("diskCleaner.deselectAll")) {
                    viewModel.deselectAll()
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.size12Medium)
                .foregroundStyle(sectionColor)

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
                    onToggleSelection: {
                        viewModel.toggleCategorySelection(result.category)
                    },
                    onToggleItem: { item in
                        viewModel.toggleItemSelection(item, in: result.category)
                    },
                    onViewDetails: {
                        viewModel.showDetails(for: result)
                    }
                )
            }
        }
    }

    // MARK: - Review Button

    private var reviewButtonSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(LFormat("diskCleaner.selected %@", viewModel.formattedSelectedSize))
                    .font(Theme.Typography.size15Semibold)

                Text(LFormat("diskCleaner.itemCount %lld", viewModel.selectedItemCount))
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassActionButton(
                LFormat("safety.notice.reviewSelected %@", viewModel.formattedSelectedSize),
                icon: "info.circle.fill",
                color: .blue,
                disabled: viewModel.selectedItemCount == 0
            ) {
                viewModel.explainSelectedStorageReview()
            }
        }
        .padding(Theme.Spacing.lg)
        .glassCard()
        .shadow(color: Color.blue.opacity(0.2), radius: 15, y: 5)
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
    let progress: Double
    let category: String
    var accentColor: Color = .blue
    var onCancel: (() -> Void)? = nil

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)

                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
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
            }

            VStack(spacing: Theme.Spacing.xxs) {
                Text(L("common.scanning"))
                    .font(Theme.Typography.size20Semibold)

                Text(category)
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)

                Text("\(Int(progress * 100))%")
                    .font(Theme.Typography.size24Bold.monospacedDigit())
                    .foregroundStyle(accentColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                        .fill(accentColor.gradient)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(Theme.Animation.spring, value: progress)
                }
            }
            .frame(width: 200, height: 8)

            // Cancel button (optional)
            if let onCancel = onCancel {
                Button(action: onCancel) {
                    Text(L("common.cancel"))
                        .font(Theme.Typography.size14Medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.small)
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 280)
        .glassCardProminent()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DiskCleanerView(viewModel: DiskCleanerViewModel(), spaceLensViewModel: SpaceLensViewModel())
        .frame(width: 800, height: 600)
}
