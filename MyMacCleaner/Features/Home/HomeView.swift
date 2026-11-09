import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    /// Opens a link in this window. Each window passes its own, since the view model is shared.
    let open: (HomeLink) -> Void
    @State private var isVisible = false

    private let sectionColor = Theme.Colors.home

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

                    // Smart Scan Button
                    smartScanSection
                        .staggeredAnimation(index: 1, isActive: isVisible)

                    // Scan Results (if available)
                    if viewModel.showScanResults {
                        ScanResultsCard(
                            results: viewModel.scanResults,
                            onOpenExperience: { open(.experience) }
                        )
                        .staggeredAnimation(index: 2, isActive: isVisible)
                    }

                    // Quick Stats
                    quickStatsSection
                        .staggeredAnimation(index: viewModel.showScanResults ? 3 : 2, isActive: isVisible)

                    // Quick Actions
                    quickActionsSection
                        .staggeredAnimation(index: viewModel.showScanResults ? 4 : 3, isActive: isVisible)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.pageTopPadding)
            }

            ToastOverlay(presenter: viewModel.toasts, onLearnWhy: { open(.trashExplanation) })
        }
        .sheet(isPresented: $viewModel.showPermissionPrompt) {
            PermissionPromptView(
                permissionsService: PermissionsService.shared,
                onDismiss: viewModel.dismissPermissionPrompt,
                onContinueWithoutPermission: viewModel.continueWithLimitedScan
            )
        }
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
        }
        .onDisappear {
            viewModel.leavePage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("navigation.home"))
                    .font(Theme.Typography.size28Bold)

                Text(L("home.subtitle"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // System status indicator
            SystemHealthPill(level: viewModel.healthLevel)
        }
    }

    // MARK: - Smart Scan Section

    private var smartScanSection: some View {
        VStack(spacing: Theme.Spacing.md) {
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

                        if viewModel.isScanning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.regular)
                                .tint(sectionColor)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(Theme.Typography.size32Medium)
                                .foregroundStyle(sectionColor.gradient)
                        }
                    }
                }

                VStack(spacing: Theme.Spacing.xs) {
                    Text(viewModel.isScanning ? L("home.scanning") : L("home.smartScan"))
                        .font(Theme.Typography.size20Semibold)

                    Text(viewModel.isScanning ? L("home.scan.analyzing") : L("home.scan.description"))
                        .font(Theme.Typography.size14)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                if viewModel.isScanning {
                    // The engine reports no per-folder progress, so the spinner above is the
                    // indicator; a caption sets expectations and Cancel is always reachable.
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(L("scan.inProgress.caption"))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)

                        GlassActionButton(
                            L("common.cancel"),
                            icon: "xmark.circle",
                            color: .secondary,
                            action: viewModel.cancelScan
                        )
                        .accessibilityIdentifier("home.scan.cancel")
                    }
                } else {
                    GlassActionButton(
                        L("home.scan.startButton"),
                        icon: "magnifyingglass",
                        color: sectionColor
                    ) {
                        viewModel.startSmartScan()
                    }
                    .accessibilityIdentifier("home.scan.start")
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity)
            .glassCard()

            if let error = viewModel.scanError {
                ScanErrorNotice(message: error)
            }

            if let coverage = viewModel.lastScanCoverage {
                if !coverage.isComplete {
                    ScanCoverageNotice(coverage: coverage, openPermissions: { open(.permissions) })
                }

                if viewModel.scanResults.isEmpty {
                    emptyResultSection(isComplete: coverage.isComplete)
                }
            }
        }
        .animation(Theme.Animation.spring, value: viewModel.isScanning)
    }

    /// A finished scan with nothing to show says so, instead of leaving an unexplained blank.
    private func emptyResultSection(isComplete: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "tray")
                .font(Theme.Typography.size32Medium)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(L("scan.empty.title"))
                .font(Theme.Typography.size20Semibold)

            Text(L(isComplete ? "scan.empty.complete" : "scan.empty.incomplete"))
                .font(Theme.Typography.size14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.scan.empty")
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("home.stats.title"))
                .font(Theme.Typography.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.md) {
                StatCard(
                    title: L("home.stats.storage"),
                    value: viewModel.storageUsed,
                    subtitle: LFormat("home.stats.of %@", viewModel.storageTotal),
                    icon: "internaldrive.fill",
                    color: Theme.Colors.storage
                )

                StatCard(
                    title: L("home.stats.memory"),
                    value: viewModel.memoryUsed,
                    subtitle: L("home.stats.inUse"),
                    icon: "memorychip.fill",
                    color: Theme.Colors.memory
                )

                StatCard(
                    title: L("home.stats.cachesAndLogs"),
                    value: viewModel.cacheAndLogSize,
                    subtitle: L("home.stats.excludesPersonal"),
                    icon: "doc.text.magnifyingglass",
                    color: Theme.Colors.storage
                )

                StatCard(
                    title: L("home.stats.apps"),
                    value: "\(viewModel.appCount)",
                    subtitle: L("home.stats.installed"),
                    icon: "square.grid.2x2.fill",
                    color: Theme.Colors.apps
                )
            }
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("home.actions.title"))
                .font(Theme.Typography.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.Spacing.md) {
                QuickActionButton(
                    title: L("safety.notice.trashReview.action"),
                    icon: "info.circle",
                    color: Theme.Colors.storage,
                    action: viewModel.explainTrashSafety
                )

                QuickActionButton(
                    title: L("home.actions.memoryGuide"),
                    icon: "memorychip",
                    color: Theme.Colors.memory,
                    action: { open(.memoryGuide) }
                )

                QuickActionButton(
                    title: L("home.actions.largeFiles"),
                    icon: "doc.fill",
                    color: Theme.Colors.home,
                    action: { open(.largeFiles) }
                )

                Spacer()
            }
        }
    }
}

// MARK: - System Health Pill

/// Non-interactive status: no hover effect, one combined accessibility element.
struct SystemHealthPill: View {
    let level: SystemHealthLevel

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: level.icon)
                .font(Theme.Typography.caption)
                .foregroundStyle(level.color)

            Text(level.label)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .glassPill()
        .help(L("home.health.basis"))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stat Card

/// Non-interactive status: no hover effect.
struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(Theme.Typography.size18Semibold)
                    .foregroundStyle(color)
            }

            Spacer()

            // Value and subtitle
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(value)
                    .font(Theme.Typography.size24Bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(Theme.Typography.size12)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
                .frame(height: 12)

            // Title
            Text(title)
                .font(Theme.Typography.size14Medium)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.md)
        .frame(height: 160)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .shadow(color: color.opacity(0.1), radius: 8, y: 5)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(color.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(Theme.Typography.size20Semibold)
                        .foregroundStyle(color)
                }
                .shadow(color: color.opacity(isHovered ? 0.4 : 0.2), radius: 8)

                Text(title)
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 120, height: 100)
            .glassCard()
        }
        .buttonStyle(GlassPressStyle(isHovered: isHovered, pressedScale: 0.95))
        .focusRing(cornerRadius: Theme.CornerRadius.large)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.1), radius: isHovered ? 12 : 6, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView(viewModel: HomeViewModel(), open: { _ in })
        .frame(width: 800, height: 600)
}
