import SwiftUI

struct OrphanedFilesView: View {
    @ObservedObject var viewModel: OrphanedFilesViewModel
    let openExperience: () -> Void
    @State private var isVisible = false

    private let sectionColor = Theme.Colors.orphans

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

                    // Content
                    if !viewModel.hasScanned && !viewModel.isScanning {
                        scanPromptSection
                            .staggeredAnimation(index: 1, isActive: isVisible)
                    } else if viewModel.orphanedFiles.isEmpty && viewModel.hasScanned {
                        emptyStateSection
                            .staggeredAnimation(index: 1, isActive: isVisible)
                    } else {
                        controlsSection
                            .staggeredAnimation(index: 1, isActive: isVisible)

                        categoryListSection
                            .staggeredAnimation(index: 2, isActive: isVisible)

                        if !viewModel.orphanedFiles.isEmpty {
                            ExperienceHandoffCard(openExperience: openExperience)
                                .staggeredAnimation(index: 3, isActive: isVisible)
                        }
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
                    category: viewModel.currentScanCategory,
                    accentColor: sectionColor,
                    onCancel: viewModel.cancelScan
                )
                .motionTransition(.scale.combined(with: .opacity))
            }

        }
        .animation(Theme.Animation.springSmooth, value: viewModel.isScanning)
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
                Text(L("navigation.orphanedFiles"))
                    .font(Theme.Typography.size28Bold)

                Text(L("navigation.orphanedFiles.description"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.hasScanned && !viewModel.orphanedFiles.isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text(viewModel.formattedTotalSize)
                            .font(Theme.Typography.size22Semibold)
                            .foregroundStyle(sectionColor)

                        Text(LFormat("orphans.filesFound %lld", Int64(viewModel.totalCount)))
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

    // MARK: - Scan Prompt

    private var scanPromptSection: some View {
        VStack(spacing: Theme.Spacing.section) {
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

                    Image(systemName: "doc.questionmark.fill")
                        .font(Theme.Typography.size32Medium)
                        .foregroundStyle(sectionColor.gradient)
                }
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("orphans.scan.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("orphans.scan.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Info about what we scan
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach([
                    ("folder.fill", L("orphans.info.applicationSupport")),
                    ("gearshape.fill", L("orphans.info.preferences")),
                    ("archivebox.fill", L("orphans.info.caches")),
                    ("shippingbox.fill", L("orphans.info.containers"))
                ], id: \.0) { icon, text in
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: icon)
                            .font(Theme.Typography.size12)
                            .foregroundStyle(sectionColor)
                            .frame(width: 20)

                        Text(text)
                            .font(Theme.Typography.size12)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .glassCard(cornerRadius: Theme.CornerRadius.medium)

            GlassActionButton(
                L("orphans.scan.startButton"),
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
                Text(L("orphans.empty.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("orphans.empty.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: viewModel.startScan) {
                Text(L("orphans.scanAgain"))
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(sectionColor)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Search
            GlassSearchField(
                text: $viewModel.searchText,
                placeholder: L("orphans.search.placeholder")
            )
            .frame(maxWidth: 250)

            // Sort
            Menu {
                ForEach(OrphanedFilesViewModel.SortOrder.allCases, id: \.self) { order in
                    Button(order.localizedName) {
                        viewModel.sortOrder = order
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.xxxs) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(viewModel.sortOrder.localizedName)
                }
                .font(Theme.Typography.size12Medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .glassCard(cornerRadius: Theme.CornerRadius.small)
            }
            .buttonStyle(.plain)

            Spacer()

            // Rescan
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
        }
    }

    // MARK: - Category List

    private var categoryListSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if viewModel.hasNoSearchMatches {
                NoSearchMatchesView(query: viewModel.searchText, onClear: viewModel.clearSearch)
            }

            ForEach(viewModel.categoriesWithFiles, id: \.self) { category in
                if let files = viewModel.filesByCategory[category], !files.isEmpty {
                    OrphanCategoryCard(
                        category: category,
                        files: files,
                        isExpanded: viewModel.expandedCategory == category,
                        onToggleExpand: {
                            viewModel.toggleCategoryExpansion(category)
                        },
                        onReveal: { file in
                            viewModel.revealInFinder(file)
                        },
                        accentColor: sectionColor
                    )
                }
            }
        }
    }

}

// MARK: - Orphan Category Card

struct OrphanCategoryCard: View {
    let category: OrphanCategory
    let files: [OrphanedFile]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onReveal: (OrphanedFile) -> Void
    let accentColor: Color

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.md) {
                    // Category icon
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(category.color.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: category.icon)
                            .font(Theme.Typography.size18)
                            .foregroundStyle(category.color)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                        Text(category.rawValue)
                            .font(Theme.Typography.size15Semibold)

                        Text(LFormat("orphans.files %lld", Int64(files.count)))
                            .font(Theme.Typography.size12)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Size
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                        .font(Theme.Typography.size14Semibold)
                        .foregroundStyle(accentColor)

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(Theme.Typography.size12Semibold)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .expandButton(isExpanded: isExpanded, action: onToggleExpand)
            }

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, Theme.Spacing.md)

                // File list
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        OrphanFileRow(file: file, onReveal: { onReveal(file) })
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .glassCard()
    }
}

// MARK: - Orphan File Row

struct OrphanFileRow: View {
    let file: OrphanedFile
    let onReveal: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // File info
            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                HStack(spacing: Theme.Spacing.xxxs) {
                    Text(file.suspectedAppName)
                        .font(Theme.Typography.size13Medium)
                        .lineLimit(1)

                    if let bundleId = file.bundleIdPattern {
                        Text("(\(bundleId))")
                            .font(Theme.Typography.size11)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Text(file.url.path)
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Date
            if let days = file.daysSinceModified {
                Text(LFormat("orphans.daysAgo %lld", Int64(days)))
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.tertiary)
            }

            // Size
            Text(file.formattedSize)
                .font(Theme.Typography.size12.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)

            // Always present, so the keyboard and VoiceOver can reach it; hover only brightens it.
            Button(action: onReveal) {
                Image(systemName: "folder")
                    .font(Theme.Typography.size12)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusRing(cornerRadius: Theme.CornerRadius.small)
            .opacity(isHovered ? 1 : 0.6)
            .help(L("common.showInFinder"))
            .accessibilityLabel(L("common.showInFinder"))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(isHovered ? Theme.Colors.subtleFill : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OrphanedFilesView(viewModel: OrphanedFilesViewModel(), openExperience: {})
        .frame(width: 800, height: 600)
}
