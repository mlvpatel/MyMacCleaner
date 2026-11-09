import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: NavigationSection = .home
    @State private var isFullScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selection: $selectedSection, homeViewModel: appState.homeViewModel)
        } detail: {
            // Detail content
            DetailContentView(
                section: selectedSection,
                appState: appState,
                onNavigate: { sectionName in
                    if let section = NavigationSection.allCases.first(where: {
                        $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == sectionName.lowercased()
                    }) {
                        withAnimation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.8), reduce: reduceMotion)) {
                            selectedSection = section
                        }
                    }
                },
                isFullScreen: isFullScreen
            )
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.selectedSection, $selectedSection)
        .frame(minWidth: 1000, minHeight: 650)
        .toolbar(removing: .sidebarToggle)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        // The menu bar's Scan request starts the Smart Scan in AppState; every window shows Home.
        .onChange(of: appState.smartScanRequests) {
            withAnimation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.8), reduce: reduceMotion)) {
                selectedSection = .home
            }
        }
    }
}

// MARK: - Navigation Section

enum NavigationSection: String, CaseIterable, Identifiable {
    case home
    case adaptiveExperience
    case diskCleaner
    case spaceLens
    case orphanedFiles
    case duplicates
    case performance
    case applications
    case startupItems
    case portManagement
    case systemHealth
    case permissions

    var id: String { rawValue }

    /// Stable, locale-independent UI test hook. Keep these identifiers independent of titles.
    var accessibilityIdentifier: String {
        switch self {
        case .home: return "navigation.home"
        case .adaptiveExperience: return "navigation.adaptive-experience"
        case .diskCleaner: return "navigation.disk-cleaner"
        case .spaceLens: return "navigation.space-lens"
        case .orphanedFiles: return "navigation.orphaned-files"
        case .duplicates: return "navigation.duplicates"
        case .performance: return "navigation.performance"
        case .applications: return "navigation.applications"
        case .startupItems: return "navigation.startup-items"
        case .portManagement: return "navigation.port-management"
        case .systemHealth: return "navigation.system-health"
        case .permissions: return "navigation.permissions"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .adaptiveExperience: return "square.stack.3d.up.fill"
        case .diskCleaner: return "internaldrive.fill"
        case .spaceLens: return "circle.hexagongrid.fill"
        case .orphanedFiles: return "doc.questionmark.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .performance: return "gauge.with.needle.fill"
        case .applications: return "square.grid.2x2.fill"
        case .startupItems: return "power.circle.fill"
        case .portManagement: return "network"
        case .systemHealth: return "heart.text.square.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var localizedName: String {
        L(key: "navigation.\(rawValue)")
    }

    /// Command-1 to Command-9 in the Go menu, in sidebar order; later sections have none.
    var goShortcut: KeyboardShortcut? {
        guard let index = Self.allCases.firstIndex(of: self), index < 9 else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character(String(index + 1))))
    }

    var localizedDescription: String {
        L(key: "navigation.\(rawValue).description")
    }

    var color: Color {
        switch self {
        case .home: return Theme.Colors.home              // Blue
        case .adaptiveExperience: return Theme.Colors.memory
        case .diskCleaner: return Theme.Colors.storage    // Orange
        case .spaceLens: return Theme.Colors.storage      // Orange
        case .orphanedFiles: return Theme.Colors.orphans  // Pink
        case .duplicates: return Theme.Colors.duplicates  // Teal
        case .performance: return Theme.Colors.memory     // Purple
        case .applications: return Theme.Colors.apps      // Green
        case .startupItems: return Theme.Colors.startup   // Yellow
        case .portManagement: return Theme.Colors.ports   // Cyan
        case .systemHealth: return Theme.Colors.health    // Red
        case .permissions: return Theme.Colors.permissions // Indigo
        }
    }
}

// MARK: - Go Menu Target

/// The key window's section, so the Go menu switches the window the user is in.
struct SelectedSectionKey: FocusedValueKey {
    typealias Value = Binding<NavigationSection>
}

extension FocusedValues {
    var selectedSection: Binding<NavigationSection>? {
        get { self[SelectedSectionKey.self] }
        set { self[SelectedSectionKey.self] = newValue }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Binding var selection: NavigationSection
    let homeViewModel: HomeViewModel
    @State private var hoveredSection: NavigationSection?

    var body: some View {
        VStack(spacing: 0) {
            // App header
            SidebarHeader()
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xs)

            // Divider
            Rectangle()
                .fill(Theme.Colors.glassStroke)
                .frame(height: 1)
                .padding(.horizontal, Theme.Spacing.md)

            // Navigation items: a sidebar List, so the arrow keys, Full Keyboard Access and
            // VoiceOver can move through it and each row reports its selected state.
            List(selection: $selection) {
                ForEach(NavigationSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section,
                        isHovered: hoveredSection == section
                    )
                    .tag(section)
                    .accessibilityIdentifier(section.accessibilityIdentifier)
                    .onHover { isHovered in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredSection = isHovered ? section : nil
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            // Bottom status
            SystemStatusBadge(viewModel: homeViewModel)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let section: NavigationSection
    let isSelected: Bool
    let isHovered: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.backgroundProminence) private var backgroundProminence

    /// The section colour, or white on the list's emphasized (accent-coloured) selection.
    private var tint: Color {
        backgroundProminence == .increased ? .white : section.color
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Icon with background
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(isSelected ? tint.opacity(0.2) : (isHovered ? Theme.Colors.surfaceLight : Color.clear))
                    .frame(width: 36, height: 36)

                Image(systemName: section.icon)
                    .font(Theme.Typography.size15Semibold)
                    .foregroundStyle(isSelected ? tint : .secondary)
            }

            // Text
            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                Text(section.localizedName)
                    .font(isSelected ? Theme.Typography.size13Semibold : Theme.Typography.size13Medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(section.localizedDescription)
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Selection indicator
            if isSelected {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.5), radius: 4)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, 10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(tint.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .strokeBorder(tint.opacity(0.2), lineWidth: 0.5)
                    }
            } else if isHovered {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.surfaceLight)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovered && !isSelected && !reduceMotion ? 1.02 : 1.0)
        .animation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.7), reduce: reduceMotion), value: isHovered)
    }
}

// MARK: - Sidebar Header

struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("SidebarLogo")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)

            Text("MyMacCleaner")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - System Status Badge

/// The Home health level from the last Smart Scan, or "Not scanned yet"; never a fixed "healthy".
/// It is not interactive, so it has no hover effect.
struct SystemStatusBadge: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: viewModel.healthLevel.icon)
                    .font(.caption)
                    .foregroundStyle(viewModel.healthLevel.color)

                Text(viewModel.healthLevel.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .help(L("home.health.basis"))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sidebar.health-status")
        }
    }
}

// MARK: - Detail Content View

struct DetailContentView: View {
    let section: NavigationSection
    let appState: AppState
    let onNavigate: (String) -> Void
    let isFullScreen: Bool

    var body: some View {
        ZStack {
            // Dynamic background gradient
            backgroundGradient
                .ignoresSafeArea()

            // Content with top padding when not in fullscreen (for toolbar spacing)
            contentView
                .padding(.top, isFullScreen ? 28 : 16)
        }
        .ignoresSafeArea(edges: .top)
        // Hide toolbar background to prevent visible bar
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    private var backgroundGradient: some View {
        ZStack {
            // Base gradient with section color
            LinearGradient(
                colors: [
                    section.color.opacity(0.15),
                    section.color.opacity(0.08),
                    section.color.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Secondary radial for depth
            RadialGradient(
                colors: [
                    section.color.opacity(0.12),
                    section.color.opacity(0.05),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 50,
                endRadius: 500
            )

            // Accent glow at bottom
            RadialGradient(
                colors: [
                    section.color.opacity(0.08),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 100,
                endRadius: 400
            )
        }
        .animation(.easeInOut(duration: 0.4), value: section)
    }

    private func openExperience() {
        onNavigate(NavigationSection.adaptiveExperience.rawValue)
    }

    /// "Learn why" on a Trash notice: Experience opens on its Trash explanation without a scan.
    private func openTrashExplanation() {
        onNavigate(appState.destination(for: .trashExplanation).rawValue)
    }

    @ViewBuilder
    private var contentView: some View {
        switch section {
        case .home:
            HomeView(viewModel: appState.homeViewModel) { link in
                onNavigate(appState.destination(for: link).rawValue)
            }
        case .adaptiveExperience:
            AdaptiveExperienceView(viewModel: appState.adaptiveExperienceViewModel)
        case .diskCleaner:
            DiskCleanerView(
                viewModel: appState.diskCleanerViewModel,
                spaceLensViewModel: appState.spaceLensViewModel,
                privacyViewModel: appState.browserPrivacyViewModel,
                openExperience: openExperience,
                openTrashExplanation: openTrashExplanation,
                openPermissions: { onNavigate(NavigationSection.permissions.rawValue) }
            )
        case .spaceLens:
            SpaceLensSectionView(viewModel: appState.spaceLensViewModel, openExperience: openExperience)
        case .orphanedFiles:
            OrphanedFilesView(viewModel: appState.orphanedFilesViewModel, openExperience: openExperience)
        case .duplicates:
            DuplicatesView(viewModel: appState.duplicatesViewModel, openExperience: openExperience)
        case .performance:
            PerformanceView(viewModel: appState.performanceViewModel)
        case .applications:
            ApplicationsView(viewModel: appState.applicationsViewModel)
        case .startupItems:
            StartupItemsView(viewModel: appState.startupItemsViewModel)
        case .portManagement:
            PortManagementView(viewModel: appState.portManagementViewModel)
        case .systemHealth:
            SystemHealthView(viewModel: appState.systemHealthViewModel)
        case .permissions:
            PermissionsView(viewModel: appState.permissionsViewModel)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
