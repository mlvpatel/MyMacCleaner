import SwiftUI
import AppKit

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @StateObject private var statsProvider = SystemStatsProvider.shared
    @StateObject private var menuBarController = MenuBarController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.horizontal, Theme.Spacing.sm)

            // Stats sections
            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                cpuSection
                memorySection
                diskSection
            }
            .padding(.vertical, Theme.Spacing.xs)

            Divider()
                .padding(.horizontal, Theme.Spacing.sm)

            // Display mode section
            displayModeSection

            Divider()
                .padding(.horizontal, Theme.Spacing.sm)

            // Actions
            actionsSection
        }
        .frame(width: 280)
        .background(VisualEffectBackground(material: .popover))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image("MenuBarIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            Text("MyMacCleaner")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - CPU Section

    private var cpuSection: some View {
        MenuBarRow(
            icon: "cpu",
            iconColor: cpuColor,
            title: L("menuBar.cpu"),
            value: statsProvider.stats.formattedCPU,
            valueColor: cpuColor,
            progress: statsProvider.stats.cpuUsage / 100,
            progressColor: cpuColor
        )
    }

    private var cpuColor: Color {
        StatusLevel.cpu(statsProvider.stats.cpuUsage / 100).color
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        let level = StatusLevel.memory(statsProvider.stats.memoryUsagePercent / 100)
        return VStack(alignment: .leading, spacing: 0) {
            MenuBarRow(
                icon: "memorychip",
                iconColor: level.color,
                title: L("menuBar.memory"),
                value: "\(statsProvider.stats.formattedMemory) / \(statsProvider.stats.formattedMemoryTotal)",
                valueColor: level.color,
                progress: statsProvider.stats.memoryUsagePercent / 100,
                progressColor: level.color
            )

            // Memory level: the icon, its color and the text all come from the same reading
            HStack(spacing: Theme.Spacing.xxxs) {
                Image(systemName: level.icon)
                    .font(.caption)
                    .foregroundStyle(level.color)
                    .accessibilityHidden(true)
                Text(level.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)
        }
    }

    // MARK: - Disk Section

    /// Disk use comes with the stats tick (read off the main thread), never from this body.
    private var diskSection: some View {
        let stats = statsProvider.stats
        let color = StatusLevel.disk(stats.diskUsageFraction).color
        return MenuBarRow(
            icon: "internaldrive",
            iconColor: color,
            title: L("menuBar.disk"),
            value: stats.formattedDisk,
            valueColor: color,
            progress: stats.diskUsageFraction,
            progressColor: color
        )
    }

    // MARK: - Display Mode Section

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(L("menuBar.displayMode"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)

            ForEach(MenuBarController.DisplayMode.allCases, id: \.rawValue) { mode in
                MenuBarButton(
                    title: mode.localizedName,
                    icon: iconForMode(mode),
                    isSelected: menuBarController.displayMode == mode
                ) {
                    menuBarController.setDisplayMode(mode)
                }
            }
        }
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func iconForMode(_ mode: MenuBarController.DisplayMode) -> String {
        switch mode {
        case .cpuOnly: return "cpu"
        case .ramOnly: return "memorychip"
        case .cpuAndRam: return "square.grid.2x2"
        case .icon: return "gauge.with.needle"
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarButton(title: L("menuBar.action.scan"), icon: "magnifyingglass") {
                openMainApp()
                runSmartScan()
            }

            MenuBarButton(title: L("menuBar.action.openApp"), icon: "macwindow") {
                openMainApp()
            }

            Divider()
                .padding(.horizontal, Theme.Spacing.sm)

            MenuBarButton(title: L("menuBar.quit"), icon: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    /// Brings the main window forward, or reopens it when it was closed. Any other visible
    /// window (the popover itself, Settings) is never mistaken for it.
    private func openMainApp() {
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow = NSApp.windows.first(where: MyMacCleanerApp.isMainWindow) {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            MyMacCleanerApp.reopenMainWindow()
        }
    }

    private func runSmartScan() {
        NotificationCenter.default.post(name: .triggerSmartScan, object: nil)
    }
}

// MARK: - Menu Bar Row Component

struct MenuBarRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let valueColor: Color
    let progress: Double
    let progressColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)

                Spacer()

                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(valueColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 4)

                    Capsule()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Menu Bar Button Component

struct MenuBarButton: View {
    let title: String
    let icon: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isHovering ? Color.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let triggerSmartScan = Notification.Name("triggerSmartScan")
}

// MARK: - Preview

#Preview {
    MenuBarView()
        .frame(height: 450)
}
