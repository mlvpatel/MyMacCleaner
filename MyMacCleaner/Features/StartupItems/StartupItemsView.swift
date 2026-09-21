import SwiftUI

// MARK: - Startup Items View

struct StartupItemsView: View {
    @ObservedObject var viewModel: StartupItemsViewModel
    @State private var isVisible = false

    // Section color for startup items
    private let sectionColor = Theme.Colors.startup

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    headerSection
                        .staggeredAnimation(index: 0, isActive: isVisible)

                    // Stats cards
                    statsSection
                        .staggeredAnimation(index: 1, isActive: isVisible)

                    // Content
                    if viewModel.items.isEmpty && !viewModel.isLoading {
                        // Initial state - show scan prompt
                        scanPromptSection
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    } else if viewModel.isLoading {
                        loadingSection
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    } else {
                        // Controls
                        controlsSection
                            .staggeredAnimation(index: 2, isActive: isVisible)

                        // Items list
                        itemsSection
                            .staggeredAnimation(index: 3, isActive: isVisible)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.pageTopPadding)
            }

            // Toast
            if viewModel.showToast {
                VStack {
                    ToastView(
                        message: viewModel.toastMessage,
                        type: viewModel.toastType,
                        onDismiss: viewModel.dismissToast
                    )
                    .padding(.top, Theme.Spacing.lg)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Animation.spring, value: viewModel.showToast)
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
                Text(L("navigation.startupItems"))
                    .font(Theme.Typography.size28Bold)

                Text(L("startupItems.subtitle"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                GlassActionButton(
                    L("startupItems.openLoginItemsSettings"),
                    icon: "gear",
                    color: sectionColor
                ) {
                    viewModel.openLoginItemsSettings()
                }

                if !viewModel.items.isEmpty {
                    GlassActionButton(
                        L("common.refresh"),
                        icon: viewModel.isLoading ? nil : "arrow.clockwise",
                        color: sectionColor,
                        disabled: viewModel.isLoading
                    ) {
                        viewModel.refreshItems()
                    }
                    .overlay {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            StartupStatCard(
                title: L("startupItems.stats.total"),
                value: "\(viewModel.items.filter { !$0.isSystemItem }.count)",
                icon: "list.bullet",
                color: .cyan
            )

            StartupStatCard(
                title: L("startupItems.stats.enabled"),
                value: "\(viewModel.enabledCount)",
                icon: "checkmark",
                color: .green
            )

            StartupStatCard(
                title: L("startupItems.stats.disabled"),
                value: "\(viewModel.disabledCount)",
                icon: "xmark",
                color: .orange
            )

            StartupStatCard(
                title: L("startupItems.stats.running"),
                value: "\(viewModel.runningCount)",
                icon: "play.fill",
                color: .purple
            )
        }
    }

    // MARK: - Scan Prompt Section

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

                    Image(systemName: "power")
                        .font(Theme.Typography.size32Medium)
                        .foregroundStyle(sectionColor.gradient)
                }
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("startupItems.scan.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("startupItems.scan.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            GlassActionButton(
                L("startupItems.scan.button"),
                icon: "magnifyingglass",
                color: sectionColor
            ) {
                viewModel.scanItems()
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 32, height: 32)

            Text(L("startupItems.scanning"))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxl)
        .glassCard()
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: Theme.ControlSize.controlSpacing) {
            // Search
            GlassSearchField(text: $viewModel.searchText, placeholder: L("startupItems.search"))

            // Type filter
            GlassMenuButton(
                icon: viewModel.selectedType?.icon ?? "line.3.horizontal.decrease.circle",
                title: viewModel.selectedType?.localizedName ?? L("startupItems.filter.allTypes")
            ) {
                Button(action: { viewModel.selectedType = nil }) {
                    HStack {
                        Text(L("startupItems.filter.allTypes"))
                        if viewModel.selectedType == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(StartupItemType.allCases, id: \.self) { type in
                    Button(action: { viewModel.selectedType = type }) {
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.localizedName)
                            if viewModel.selectedType == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Sort order
            GlassMenuButton(
                icon: "arrow.up.arrow.down",
                title: viewModel.sortOrder.localizedName
            ) {
                ForEach(StartupItemsViewModel.SortOrder.allCases, id: \.self) { order in
                    Button(action: { viewModel.sortOrder = order }) {
                        HStack {
                            Image(systemName: order.icon)
                            Text(order.localizedName)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Spacer()

            // Show system items toggle
            GlassToggle(title: L("startupItems.systemItems"), isOn: $viewModel.showSystemItems)
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if viewModel.filteredItems.isEmpty {
                emptyFilterSection
            } else {
                ForEach(viewModel.filteredItems) { item in
                    StartupItemRow(
                        item: item,
                        onReveal: { viewModel.revealInFinder(item) }
                    )
                }
            }
        }
    }

    private var emptyFilterSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.size48)
                .foregroundStyle(.tertiary)

            Text(L("startupItems.empty.title"))
                .font(Theme.Typography.headline)

            Text(L("startupItems.empty.message"))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxl)
        .glassCard()
    }
}

// MARK: - Startup Stat Card

struct StartupStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(Theme.Typography.size18Semibold)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                Text(value)
                    .font(Theme.Typography.title2.monospacedDigit())

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .glassCard()
        .hoverEffect(isHovered: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Startup Item Row

struct StartupItemRow: View {
    let item: StartupItem
    let onReveal: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: Theme.Spacing.md) {
                // Type icon with status indicator
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(item.typeColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: item.icon)
                        .font(Theme.Typography.size18Semibold)
                        .foregroundStyle(item.typeColor)

                    // Running indicator
                    if item.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
                            )
                            .offset(x: 16, y: -16)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(item.displayName)
                            .font(Theme.Typography.subheadline.weight(.medium))
                            .lineLimit(1)

                        if item.isSystemItem {
                            Text(L("startupItems.badge.system"))
                                .font(Theme.Typography.size9Medium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Theme.Spacing.xxxs)
                                .padding(.vertical, Theme.Spacing.tiny)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny))
                        }
                    }

                    Text(item.label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if let developer = item.developer {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: "building.2")
                                .font(Theme.Typography.size9)
                            Text(developer)
                                .font(Theme.Typography.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Type badge
                Text(item.type.localizedName)
                    .font(Theme.Typography.size10Medium)
                    .foregroundStyle(item.typeColor)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(item.typeColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny))

                // Status indicator
                HStack(spacing: Theme.Spacing.xxs) {
                    Circle()
                        .fill(item.isEnabled ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(item.isEnabled ? L("startupItems.status.enabled") : L("startupItems.status.disabled"))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80)

                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(Theme.Typography.size16)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("common.showInFinder"))
                .opacity(isHovered ? 1 : 0.6)
            }
            .padding(Theme.Spacing.md)
            .background(isHovered ? Color.white.opacity(0.03) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Theme.Animation.spring) {
                    isExpanded.toggle()
                }
            }
            .onHover { isHovered = $0 }

            // Expanded details
            if isExpanded {
                Divider()
                    .padding(.horizontal, Theme.Spacing.md)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    DetailRow(label: L("startupItems.detail.label"), value: item.label)
                    DetailRow(label: L("startupItems.detail.path"), value: item.path)
                    if let execPath = item.executablePath {
                        DetailRow(label: L("startupItems.detail.executable"), value: execPath)
                    }
                    if let bundleId = item.bundleIdentifier {
                        DetailRow(label: L("startupItems.detail.bundleId"), value: bundleId)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Color.white.opacity(0.02))
            }
        }
        .glassCard()
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)

            Text(value)
                .font(Theme.Typography.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    StartupItemsView(viewModel: StartupItemsViewModel())
        .frame(width: 900, height: 700)
}
