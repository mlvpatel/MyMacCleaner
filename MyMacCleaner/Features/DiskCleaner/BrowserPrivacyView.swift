import SwiftUI

// MARK: - Browser Privacy View Model

/// Read-only browser-data inventory: it lists what each browser stores and never changes it.
@MainActor
class BrowserPrivacyViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var hasScanned = false

    @Published var items: [BrowserDataItem] = []
    /// Installed browsers the last scan could not read, so an empty list is never called clean.
    @Published private(set) var unreadableBrowsers: [BrowserType] = []

    private let scanBrowsers: @Sendable () async -> BrowserScan
    private var scanTask: Task<Void, Never>?

    init(scanBrowsers: @escaping @Sendable () async -> BrowserScan = {
        await BrowserCleanerService.shared.scanAllBrowsers()
    }) {
        self.scanBrowsers = scanBrowsers
    }

    // MARK: - Computed Properties

    var installedBrowsers: [BrowserType] {
        BrowserType.allCases.filter { $0.isInstalled }
    }

    var itemsByBrowser: [BrowserType: [BrowserDataItem]] {
        Dictionary(grouping: items, by: { $0.browser })
    }

    // MARK: - Actions

    func scan() {
        guard !isScanning else { return }
        // The last results stay until this scan finishes, so a stopped rescan keeps them.
        isScanning = true

        scanTask = Task { [scanBrowsers] in
            let scan = await scanBrowsers()
            // A cancelled scan stopped part-way; never present it.
            guard !Task.isCancelled else { return }
            items = scan.items
            unreadableBrowsers = scan.unreadableBrowsers
            hasScanned = true
            isScanning = false
            scanTask = nil
        }
    }

    /// Stops an in-flight scan, for example when the page goes away.
    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
}

// MARK: - Browser Privacy View

struct BrowserPrivacyView: View {
    @ObservedObject var viewModel: BrowserPrivacyViewModel
    let openExperience: () -> Void
    let openPermissions: () -> Void
    @State private var expandedBrowser: BrowserType?

    private let privacyColor = Color.orange

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if viewModel.hasScanned && !viewModel.unreadableBrowsers.isEmpty {
                ScanCoverageNotice(
                    deniedText: LFormat(
                        "privacy.coverage.denied %@",
                        viewModel.unreadableBrowsers.map(\.rawValue).joined(separator: ", ")
                    ),
                    openPermissions: openPermissions
                )
            }

            if !viewModel.hasScanned && !viewModel.isScanning {
                scanPromptSection
            } else if viewModel.items.isEmpty && viewModel.hasScanned {
                emptyStateSection
            } else {
                browserListSection
                if !viewModel.items.isEmpty {
                    ExperienceHandoffCard(openExperience: openExperience)
                }
            }
        }
        .overlay {
            if viewModel.isScanning {
                ScanningOverlay(
                    progress: nil,
                    category: L("privacy.scanning"),
                    accentColor: privacyColor
                )
            }
        }
        .onDisappear {
            viewModel.cancelScan()
        }
    }

    // MARK: - Scan Prompt

    private var scanPromptSection: some View {
        VStack(spacing: Theme.Spacing.section) {
            ZStack {
                Circle()
                    .fill(privacyColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Circle()
                                .strokeBorder(privacyColor.opacity(0.3), lineWidth: 1)
                        }

                    Image(systemName: "hand.raised.fill")
                        .font(Theme.Typography.size32Medium)
                        .foregroundStyle(privacyColor.gradient)
                }
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("privacy.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L("privacy.description"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Installed browsers
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(viewModel.installedBrowsers) { browser in
                    HStack(spacing: Theme.Spacing.xxxs) {
                        Image(systemName: browser.icon)
                            .font(Theme.Typography.size14)
                        Text(browser.rawValue)
                            .font(Theme.Typography.size13)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            GlassActionButton(
                L("privacy.scan"),
                icon: "magnifyingglass",
                color: privacyColor
            ) {
                viewModel.scan()
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Empty State

    /// No green check when a browser could not be read: the empty list may only be what was readable.
    private var emptyStateSection: some View {
        let isComplete = viewModel.unreadableBrowsers.isEmpty
        return VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "tray")
                .font(Theme.Typography.size48)
                .foregroundStyle(isComplete ? .green : .secondary)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.xs) {
                Text(L("privacy.empty.title"))
                    .font(Theme.Typography.size20Semibold)

                Text(L(isComplete ? "privacy.empty.description" : "privacy.empty.incomplete"))
                    .font(Theme.Typography.size14)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: viewModel.scan) {
                Text(L("privacy.scanAgain"))
                    .font(Theme.Typography.size13Medium)
                    .foregroundStyle(privacyColor)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Browser List

    private var browserListSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Header
            HStack {
                Text(L("privacy.browserData"))
                    .font(Theme.Typography.headline)

                Spacer()

                Button(action: viewModel.scan) {
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

            // Browser cards
            ForEach(viewModel.installedBrowsers) { browser in
                if let browserItems = viewModel.itemsByBrowser[browser], !browserItems.isEmpty {
                    BrowserDataCard(
                        browser: browser,
                        items: browserItems,
                        isExpanded: expandedBrowser == browser,
                        onToggleExpand: {
                            withAnimation(Theme.Animation.spring) {
                                expandedBrowser = expandedBrowser == browser ? nil : browser
                            }
                        },
                        accentColor: privacyColor
                    )
                }
            }
        }
    }
}

// MARK: - Browser Data Card

struct BrowserDataCard: View {
    let browser: BrowserType
    let items: [BrowserDataItem]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let accentColor: Color

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.md) {
                    // Browser icon
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: browser.icon)
                            .font(Theme.Typography.size18)
                            .foregroundStyle(accentColor)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                        Text(browser.rawValue)
                            .font(Theme.Typography.size15Semibold)

                        Text(LFormat("privacy.items %lld", Int64(items.count)))
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

                VStack(spacing: 0) {
                    ForEach(items) { item in
                        BrowserDataItemRow(item: item, accentColor: accentColor)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .glassCard()
    }
}

// MARK: - Browser Data Item Row

struct BrowserDataItemRow: View {
    let item: BrowserDataItem
    let accentColor: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Icon
            Image(systemName: item.dataType.icon)
                .font(Theme.Typography.size14)
                .foregroundStyle(accentColor.opacity(0.8))
                .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                HStack(spacing: Theme.Spacing.xxxs) {
                    Text(item.dataType.rawValue)
                        .font(Theme.Typography.size13Medium)

                    // Warning indicator
                    if let warning = item.dataType.warningLevel.message {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.size10)
                            .foregroundStyle(.orange)
                            .help(warning)
                    }
                }

                Text(item.dataType.description)
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Size
            Text(item.formattedSize)
                .font(Theme.Typography.size12.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Preview

#Preview {
    BrowserPrivacyView(viewModel: BrowserPrivacyViewModel(), openExperience: {}, openPermissions: {})
        .frame(width: 600, height: 500)
}
