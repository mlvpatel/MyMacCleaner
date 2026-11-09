import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var viewModel: DuplicatesViewModel
    let openExperience: () -> Void
    @State private var isVisible = false
    @State private var expandedGroup: UUID?

    private let sectionColor = Theme.Colors.duplicates

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
                    } else if viewModel.duplicateGroups.isEmpty && viewModel.hasScanned {
                        emptyStateSection
                            .staggeredAnimation(index: 1, isActive: isVisible)
                    } else {
                        // Stats overview
                        statsSection
                            .staggeredAnimation(index: 1, isActive: isVisible)

                        // Controls
                        controlsSection
                            .staggeredAnimation(index: 2, isActive: isVisible)

                        // Duplicate groups list
                        duplicateListSection
                            .staggeredAnimation(index: 3, isActive: isVisible)

                        if !viewModel.duplicateGroups.isEmpty {
                            ExperienceHandoffCard(openExperience: openExperience)
                                .staggeredAnimation(index: 4, isActive: isVisible)
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
                    category: viewModel.currentScanStatus,
                    accentColor: sectionColor,
                    onCancel: { viewModel.cancelScan() }
                )
                .motionTransition(.scale.combined(with: .opacity))
            }

            ToastOverlay(presenter: viewModel.toasts)
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
                Text(L("navigation.duplicates"))
                    .font(Theme.Typography.size28Bold)

                HStack(spacing: Theme.Spacing.xs) {
                    Text(L("navigation.duplicates.description"))
                        .font(Theme.Typography.size13)
                        .foregroundStyle(.secondary)

                    if viewModel.hasScanned {
                        Text("•")
                            .foregroundStyle(.tertiary)

                        Button(action: viewModel.chooseScanLocation) {
                            HStack(spacing: Theme.Spacing.xxs) {
                                Image(systemName: "folder.fill")
                                    .font(Theme.Typography.size10)
                                Text(viewModel.scanPath.lastPathComponent)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(Theme.Typography.size8)
                            }
                            .font(Theme.Typography.size12)
                            .foregroundStyle(sectionColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.hasScanned && viewModel.isTruncated {
                    Text(LFormat("duplicates.truncated %lld", Int64(DuplicateScanLimits.maxEntries)))
                        .font(Theme.Typography.size11)
                        .foregroundStyle(.orange)
                }

                if viewModel.hasScanned && viewModel.skippedCloudOnlyCount > 0 {
                    Text(LFormat("duplicates.cloudOnlySkipped %lld", Int64(viewModel.skippedCloudOnlyCount)))
                        .font(Theme.Typography.size11)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.hasScanned && !viewModel.duplicateGroups.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    // Rescan button
                    Button(action: viewModel.startScan) {
                        Image(systemName: "arrow.clockwise")
                            .font(Theme.Typography.size14)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("duplicates.scanAgain"))

                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text(viewModel.formattedTotalWastedSize)
                            .font(Theme.Typography.size22Semibold)
                            .foregroundStyle(sectionColor)

                        Text(LFormat("duplicates.wastedSpace %lld", Int64(viewModel.totalGroupCount)))
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

                    Image(systemName: "doc.on.doc.fill")
                        .font(Theme.Typography.size32Medium)
                        .foregroundStyle(sectionColor.gradient)
                }
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("duplicates.scan.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("duplicates.scan.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Scan location
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(sectionColor)

                    Text(viewModel.scanPath.path)
                        .font(Theme.Typography.size13)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(L("duplicates.chooseFolder")) {
                        viewModel.chooseScanLocation()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.size12Medium)
                    .foregroundStyle(sectionColor)
                }
                .padding(Theme.Spacing.sm)
                .glassCard(cornerRadius: Theme.CornerRadius.medium)
            }

            GlassActionButton(
                L("duplicates.scan.startButton"),
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
                Text(L("duplicates.empty.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("duplicates.empty.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Current scan location
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "folder.fill")
                    .font(Theme.Typography.size12)
                    .foregroundStyle(.secondary)

                Text(viewModel.scanPath.lastPathComponent)
                    .font(Theme.Typography.size12)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxxs)
            .background(Theme.Colors.surfaceLight)
            .cornerRadius(Theme.CornerRadius.xs)

            HStack(spacing: Theme.Spacing.md) {
                Button(action: viewModel.chooseScanLocation) {
                    HStack(spacing: Theme.Spacing.xxxs) {
                        Image(systemName: "folder.badge.gearshape")
                        Text(L("duplicates.changeFolder"))
                    }
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: viewModel.startScan) {
                    HStack(spacing: Theme.Spacing.xxxs) {
                        Image(systemName: "arrow.clockwise")
                        Text(L("duplicates.scanAgain"))
                    }
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(sectionColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(viewModel.fileTypeStats.prefix(4), id: \.0) { type, count, size in
                VStack(spacing: Theme.Spacing.xs) {
                    ZStack {
                        Circle()
                            .fill(type.color.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: type.icon)
                            .font(Theme.Typography.size16)
                            .foregroundStyle(type.color)
                    }

                    VStack(spacing: Theme.Spacing.tiny) {
                        Text("\(count)")
                            .font(Theme.Typography.size16Semibold)

                        Text(type.rawValue)
                            .font(Theme.Typography.size11)
                            .foregroundStyle(.secondary)

                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(Theme.Typography.size10)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .glassCard(cornerRadius: Theme.CornerRadius.medium)
                .pressable(cornerRadius: Theme.CornerRadius.medium) {
                    if viewModel.filterType == type {
                        viewModel.filterType = nil
                    } else {
                        viewModel.filterType = type
                    }
                }
                .accessibilityValue(L(viewModel.filterType == type ? "common.filterOn" : "common.filterOff"))
                .overlay {
                    if viewModel.filterType == type {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .strokeBorder(sectionColor, lineWidth: 2)
                    }
                }
            }
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: Theme.ControlSize.controlSpacing) {
            // Search
            GlassSearchField(
                text: $viewModel.searchText,
                placeholder: L("duplicates.search.placeholder")
            )

            // Sort
            GlassMenuButton(
                icon: "arrow.up.arrow.down",
                title: viewModel.sortOrder.localizedName
            ) {
                ForEach(DuplicatesViewModel.SortOrder.allCases, id: \.self) { order in
                    Button(order.localizedName) {
                        viewModel.sortOrder = order
                    }
                }
            }

            if viewModel.filterType != nil || !viewModel.searchText.isEmpty {
                Button(action: viewModel.clearFilter) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "xmark.circle.fill")
                        Text(L("duplicates.clearFilters"))
                    }
                    .font(Theme.ControlSize.controlFont)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Rescan
            Button(action: viewModel.startScan) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "arrow.clockwise")
                    Text(L("diskCleaner.rescan"))
                }
                .font(Theme.ControlSize.controlFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.ControlSize.horizontalPadding)
                .padding(.vertical, Theme.ControlSize.verticalPadding)
                .frame(height: Theme.ControlSize.toolbarHeight)
                .glassCard(cornerRadius: Theme.ControlSize.controlRadius)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Duplicate List

    private var duplicateListSection: some View {
        LazyVStack(spacing: Theme.Spacing.sm) {
            if viewModel.hasNoSearchMatches {
                NoSearchMatchesView(
                    query: viewModel.searchText,
                    clearTitle: L("duplicates.clearFilters"),
                    onClear: viewModel.clearFilter
                )
            }

            ForEach(viewModel.filteredGroups) { group in
                DuplicateGroupCard(
                    group: group,
                    isExpanded: expandedGroup == group.id,
                    onToggleExpand: {
                        withAnimation(Theme.Animation.spring) {
                            expandedGroup = expandedGroup == group.id ? nil : group.id
                        }
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

// MARK: - Duplicate Group Card

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onReveal: (DuplicateFile) -> Void
    let accentColor: Color

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.md) {
                    // File type icon
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(group.fileType.color.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: group.fileType.icon)
                            .font(Theme.Typography.size18)
                            .foregroundStyle(group.fileType.color)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                        Text(group.files.first?.name ?? "Unknown")
                            .font(Theme.Typography.size15Semibold)
                            .lineLimit(1)

                        HStack(spacing: Theme.Spacing.xs) {
                            Text(LFormat("duplicates.copies %lld", Int64(group.files.count)))
                                .font(Theme.Typography.size12)
                                .foregroundStyle(.secondary)

                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(group.formattedSize)
                                .font(Theme.Typography.size12)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Wasted size
                    VStack(alignment: .trailing, spacing: Theme.Spacing.tiny) {
                        Text(group.formattedWastedSize)
                            .font(Theme.Typography.size14Semibold)
                            .foregroundStyle(accentColor)

                        Text(L("duplicates.wasted"))
                            .font(Theme.Typography.size11)
                            .foregroundStyle(.tertiary)
                    }

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

                VStack(spacing: 0) {
                    ForEach(group.files) { file in
                        DuplicateFileRow(file: file, onReveal: { onReveal(file) })
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .glassCard()
    }
}

// MARK: - Duplicate File Row

struct DuplicateFileRow: View {
    let file: DuplicateFile
    let onReveal: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // File info
            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                Text(file.parentFolder)
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(.primary)

                Text(file.url.path)
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Date
            Text(file.formattedDate)
                .font(Theme.Typography.size11)
                .foregroundStyle(.tertiary)

            // Size
            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(Theme.Typography.size11.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)

            // Reveal in Finder - always visible
            Button(action: onReveal) {
                Image(systemName: "folder")
                    .font(Theme.Typography.size12)
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .help(L("common.revealInFinder"))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(isHovered ? Theme.Colors.subtleFill : Color.clear)
        )
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
    DuplicatesView(viewModel: DuplicatesViewModel(), openExperience: {})
        .frame(width: 900, height: 700)
}
