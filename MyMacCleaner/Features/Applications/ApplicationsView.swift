import SwiftUI

// MARK: - Applications View

struct ApplicationsView: View {
    @ObservedObject var viewModel: ApplicationsViewModel
    @State private var isVisible = false
    @State private var selectedTab: AppTab = .allApps

    enum AppTab: String, CaseIterable {
        case allApps
        case homebrew

        var icon: String {
            switch self {
            case .allApps: return "square.grid.2x2"
            case .homebrew: return "shippingbox"
            }
        }

        var localizedName: String {
            L(key: "applications.tab.\(rawValue)")
        }
    }

    // Section color for applications
    private let sectionColor = Theme.Colors.apps

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    headerSection
                        .staggeredAnimation(index: 0, isActive: isVisible)

                    // Show different content based on state
                    if viewModel.analysisState == .completed {
                        // Tab picker
                        tabPicker
                            .staggeredAnimation(index: 1, isActive: isVisible)

                        // Tab content
                        switch selectedTab {
                        case .allApps:
                            controlsSection
                                .staggeredAnimation(index: 2, isActive: isVisible)

                            if viewModel.filteredApps.isEmpty {
                                emptySection
                            } else {
                                appGridSection
                                    .staggeredAnimation(index: 3, isActive: isVisible)
                            }

                        case .homebrew:
                            homebrewSection
                                .staggeredAnimation(index: 2, isActive: isVisible)
                        }
                    } else {
                        // Discovery / Pre-analysis view
                        infoCardsSection
                            .staggeredAnimation(index: 1, isActive: isVisible)

                        analysisSection
                            .staggeredAnimation(index: 2, isActive: isVisible)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.pageTopPadding)
            }
        }
        .animation(Theme.Animation.spring, value: viewModel.analysisState)
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
            // Start background discovery when view appears
            viewModel.startBackgroundDiscovery()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("navigation.applications"))
                    .font(Theme.Typography.size28Bold)

                Text(L("applications.subtitle"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.analysisState == .completed {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text(viewModel.formattedTotalSize)
                            .font(Theme.Typography.size22Semibold)
                            .foregroundStyle(sectionColor)

                        Text(LFormat("applications.appsInstalled %lld", viewModel.applications.count))
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

    // MARK: - Info Cards Section

    private var infoCardsSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Apps Found Card
            InfoCard(
                icon: "square.grid.2x2.fill",
                iconColor: .cyan,
                title: "\(viewModel.applications.count)",
                subtitle: L("applications.stats.appsFound"),
                isLoading: viewModel.discoveryState == .discovering
            )

            // System Apps Card
            InfoCard(
                icon: "gearshape.fill",
                iconColor: .orange,
                title: "\(systemAppsCount)",
                subtitle: L("applications.stats.systemApps"),
                isLoading: viewModel.discoveryState == .discovering
            )

            // User Apps Card
            InfoCard(
                icon: "person.fill",
                iconColor: .purple,
                title: "\(userAppsCount)",
                subtitle: L("applications.stats.userApps"),
                isLoading: viewModel.discoveryState == .discovering
            )

            // Analysis Status Card
            InfoCard(
                icon: viewModel.analysisState == .analyzing ? "arrow.triangle.2.circlepath" : "chart.bar.fill",
                iconColor: .green,
                title: viewModel.analysisState == .analyzing ? "\(Int(viewModel.analysisProgress * 100))%" : L("applications.stats.ready"),
                subtitle: viewModel.analysisState == .analyzing ? L("applications.stats.analyzing") : L("applications.stats.toAnalyze"),
                isLoading: viewModel.analysisState == .analyzing
            )
        }
    }

    private var systemAppsCount: Int {
        viewModel.applications.filter { $0.url.path.hasPrefix("/Applications") }.count
    }

    private var userAppsCount: Int {
        viewModel.applications.filter { !$0.url.path.hasPrefix("/Applications") }.count
    }

    // MARK: - Analysis Section

    private var analysisSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if viewModel.analysisState == .analyzing {
                // Progress view
                VStack(spacing: Theme.Spacing.md) {
                    // Progress bar
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text(L("applications.analyzing"))
                                .font(Theme.Typography.headline)

                            Spacer()

                            Text("\(viewModel.appsWithSizeCalculated) / \(viewModel.applications.count)")
                                .font(Theme.Typography.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: viewModel.analysisProgress)
                            .progressViewStyle(.linear)
                            .tint(.cyan)

                        if !viewModel.currentAppBeingAnalyzed.isEmpty {
                            Text(LFormat("applications.calculatingSize %@", viewModel.currentAppBeingAnalyzed))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .glassCard()
                }
            } else {
                // Start Analysis button
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

                            Image(systemName: "square.grid.2x2")
                                .font(Theme.Typography.size32Medium)
                                .foregroundStyle(sectionColor.gradient)
                        }
                    }

                    VStack(spacing: Theme.Spacing.xs) {
                        Text(L("applications.analyze.title"))
                            .font(Theme.Typography.size20Semibold)

                        Text(L("applications.analyze.description"))
                            .font(Theme.Typography.size14)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }

                    // Start button
                    GlassActionButton(
                        L("applications.analyze.button"),
                        icon: "play.fill",
                        color: sectionColor,
                        disabled: viewModel.discoveryState == .discovering && viewModel.applications.isEmpty
                    ) {
                        viewModel.startFullAnalysis()
                    }

                    // Discovery status
                    if viewModel.discoveryState == .discovering {
                        HStack(spacing: Theme.Spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)

                            Text(L("applications.discovering"))
                                .font(Theme.Typography.size11)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(Theme.Spacing.xxl)
                .frame(maxWidth: .infinity)
                .glassCard()
            }

            // App preview (show some apps without sizes during discovery)
            if !viewModel.applications.isEmpty && viewModel.analysisState != .analyzing {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text(L("applications.discoveredApps"))
                            .font(Theme.Typography.headline)

                        Spacer()

                        if viewModel.discoveryState == .discovering {
                            HStack(spacing: Theme.Spacing.xxxs) {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 10, height: 10)
                                Text(L("applications.discoveringShort"))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Show first 8 apps as preview
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                        ForEach(Array(viewModel.applications.prefix(8))) { app in
                            AppPreviewCard(app: app)
                        }

                        if viewModel.applications.count > 8 {
                            MoreAppsCard(count: viewModel.applications.count - 8)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .glassCard()
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack {
            GlassTabPicker(
                tabs: AppTab.allCases,
                selection: $selectedTab,
                icon: { $0.icon },
                label: { $0.localizedName },
                accentColor: sectionColor
            )

            Spacer()
        }
    }

    // MARK: - Homebrew Section

    private var homebrewSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if !viewModel.isHomebrewInstalled {
                // Homebrew not installed
                VStack(spacing: Theme.Spacing.lg) {
                    Image(systemName: "shippingbox")
                        .font(Theme.Typography.size48)
                        .foregroundStyle(.tertiary)

                    Text(L("applications.homebrew.notInstalled"))
                        .font(Theme.Typography.headline)

                    Text(L("applications.homebrew.description"))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Link(destination: URL(string: "https://brew.sh")!) {
                        HStack {
                            Image(systemName: "globe")
                            Text(L("applications.homebrew.visit"))
                        }
                        .font(Theme.Typography.size13Medium)
                        .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xxl)
                .glassCard()
            } else {
                // Homebrew inventory header
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(L("applications.homebrew.casks"))
                            .font(Theme.Typography.headline)

                        Text(LFormat("applications.homebrew.casksInstalled %lld", viewModel.homebrewCasks.count))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.isLoadingHomebrew {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        GlassActionButton(
                            L("common.refresh"),
                            icon: "arrow.clockwise",
                            color: sectionColor
                        ) {
                            viewModel.loadHomebrewStatus()
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .glassCard()

                if viewModel.isHomebrewInventoryUnavailable {
                    Text(L("applications.homebrew.inventoryUnavailable"))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .glassCard()
                }

                // All casks
                if viewModel.homebrewCasks.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "shippingbox")
                            .font(Theme.Typography.size48)
                            .foregroundStyle(.tertiary)

                        Text(L("applications.homebrew.noCasks"))
                            .font(Theme.Typography.headline)

                        Text(L("applications.homebrew.installHint"))
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.xxl)
                    .glassCard()
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text(L("applications.homebrew.installed"))
                            .font(Theme.Typography.headline)

                        ForEach(viewModel.homebrewCasks, id: \.name) { cask in
                            HomebrewCaskRow(cask: cask)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .glassCard()
                }
            }
        }
        .onAppear {
            viewModel.loadHomebrewStatus()
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: Theme.ControlSize.controlSpacing) {
            // Search
            GlassSearchField(text: $viewModel.searchText, placeholder: L("applications.search"))

            // Sort picker
            GlassMenuButton(
                icon: "arrow.up.arrow.down",
                title: viewModel.sortOrder.localizedName
            ) {
                ForEach(ApplicationsViewModel.SortOrder.allCases, id: \.self) { order in
                    Button(action: { viewModel.sortOrder = order }) {
                        HStack {
                            Text(order.localizedName)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Refresh button
            GlassActionButton(
                L("common.refresh"),
                icon: "arrow.clockwise",
                color: sectionColor
            ) {
                viewModel.refresh()
            }
        }
    }

    // MARK: - Empty Section

    private var emptySection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.size48)
                .foregroundStyle(.tertiary)

            Text(L("applications.empty.title"))
                .font(Theme.Typography.headline)

            Text(L("applications.empty.message"))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    // MARK: - App Grid Section

    private var appGridSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
            ForEach(viewModel.filteredApps) { app in
                AppCard(
                    app: app,
                    onOpen: { viewModel.openApp(app) },
                    onReveal: { viewModel.revealInFinder(app) }
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ApplicationsView(viewModel: ApplicationsViewModel())
        .frame(width: 900, height: 700)
}
