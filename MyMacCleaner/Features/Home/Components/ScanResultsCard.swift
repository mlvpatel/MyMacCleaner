import SwiftUI

// MARK: - Scan Results Card

struct ScanResultsCard: View {
    let results: [ScanResult]
    let onOpenExperience: () -> Void

    @State private var isVisible = false
    @State private var expandedCategories: Set<ScanCategory> = []
    @State private var allExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var totalSize: Int64 {
        results.reduce(0) { $0 + $1.totalSize }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Header
            headerSection

            // Category breakdown
            categoryBreakdown

            // Expand / collapse
            actionButtons

            ExperienceHandoffCard(openExperience: onOpenExperience)
        }
        .padding(Theme.Spacing.lg)
        .glassCardProminent()
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion ? 0 : 20)
        .onAppear {
            withAnimation(Theme.Animation.motion(Theme.Animation.springSmooth, reduce: reduceMotion)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("scanResults.title"))
                    .font(Theme.Typography.title2)

                Text(LFormat("scanResults.categoriesFound %lld", results.count))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Total size badge
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(Theme.Typography.title)
                    .foregroundStyle(.orange)

                Text(L("scanResults.found"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Category Breakdown

    private var categoryBreakdown: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // Sort results by size and iterate safely using stable identifiers
            ForEach(results.sorted { $0.totalSize > $1.totalSize }) { result in
                ScanResultRow(
                    result: result,
                    isExpanded: expandedCategories.contains(result.category),
                    onToggleExpand: {
                        withAnimation(Theme.Animation.spring) {
                            if expandedCategories.contains(result.category) {
                                expandedCategories.remove(result.category)
                            } else {
                                expandedCategories.insert(result.category)
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: Theme.Spacing.md) {
            // View all / Collapse all button
            Button(action: {
                withAnimation(Theme.Animation.spring) {
                    if allExpanded {
                        expandedCategories.removeAll()
                    } else {
                        expandedCategories = Set(results.map { $0.category })
                    }
                    allExpanded.toggle()
                }
            }) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: allExpanded ? "chevron.up.2" : "list.bullet")
                    Text(allExpanded ? L("scanResults.collapseAll") : L("scanResults.viewAll"))
                }
                .font(Theme.Typography.subheadline)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .glassCardSubtle()
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Scan Result Row

struct ScanResultRow: View {
    let result: ScanResult
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row content
            HStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.md) {
                    // Category icon
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .fill(result.category.color.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: result.category.icon)
                            .font(Theme.Typography.size14Semibold)
                            .foregroundStyle(result.category.color)
                    }

                    // Category info
                    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                        Text(result.category.localizedName)
                            .font(Theme.Typography.body)
                            .foregroundStyle(.primary)

                        Text(LFormat("scanResults.items %lld", result.itemCount))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Size
                    Text(ByteCountFormatter.string(fromByteCount: result.totalSize, countStyle: .file))
                        .font(Theme.Typography.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    // Expand/Collapse chevron
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
                .expandButton(isExpanded: isExpanded, cornerRadius: Theme.CornerRadius.medium, action: onToggleExpand)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(isHovered ? Theme.Colors.surfaceLight : Color.clear)
            )
            .onHover { hovering in
                withAnimation(Theme.Animation.fast) {
                    isHovered = hovering
                }
            }

            // Expanded content - show individual files
            if isExpanded {
                Divider()
                    .padding(.horizontal, Theme.Spacing.md)

                VStack(spacing: 0) {
                    // Show files with a max of 10, then indicate more
                    let itemsToShow = Array(result.items.sorted(by: { $0.size > $1.size }).prefix(10))

                    ForEach(itemsToShow) { item in
                        ScanFileItemRow(item: item)
                    }

                    // Show "and X more" if there are more items
                    if result.items.count > 10 {
                        HStack {
                            Spacer()
                            Text(LFormat("scanResults.andMore %lld", result.items.count - 10))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, Theme.Spacing.sm)
                            Spacer()
                        }
                        .background(Theme.Colors.subtleFill)
                    }
                }
                .background(Theme.Colors.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .glassCard()
        .animation(Theme.Animation.spring, value: isExpanded)
    }
}

// MARK: - Cleanable Item Row

struct ScanFileItemRow: View {
    let item: CleanableItem

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // File type icon
            Image(systemName: fileIcon)
                .font(Theme.Typography.size12)
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            // File name
            Text(item.name)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Modified date
            if item.modificationDate != nil {
                Text(item.formattedDate)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }

            // Size
            Text(item.formattedSize)
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)

            // Always present, so the keyboard and VoiceOver can reach it; hover only brightens it.
            Button(action: {
                NSWorkspace.shared.selectFile(item.path.path, inFileViewerRootedAtPath: item.path.deletingLastPathComponent().path)
            }) {
                Image(systemName: "folder")
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .focusRing(cornerRadius: Theme.CornerRadius.small)
            .opacity(isHovered ? 1 : 0.6)
            .help(L("common.showInFinder"))
            .accessibilityLabel(L("common.showInFinder"))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xxxs)
        .background(isHovered ? Theme.Colors.subtleFill : Color.clear)
        .onHover { hovering in
            withAnimation(Theme.Animation.fast) {
                isHovered = hovering
            }
        }
    }

    private var fileIcon: String {
        let ext = item.path.pathExtension.lowercased()
        switch ext {
        case "app": return "app.fill"
        case "dmg", "pkg": return "shippingbox.fill"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "log", "txt": return "doc.text"
        case "json", "xml", "plist": return "doc.badge.gearshape"
        case "": return "folder.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        let results: [ScanResult] = [
            ScanResult(
                category: .caches,
                items: [
                    CleanableItem(
                        name: "test.cache",
                        path: URL(fileURLWithPath: "/tmp/test"),
                        size: 1024 * 1024 * 500,
                        modificationDate: Date(),
                        category: .caches
                    ),
                    CleanableItem(
                        name: "another.cache",
                        path: URL(fileURLWithPath: "/tmp/another"),
                        size: 1024 * 1024 * 100,
                        modificationDate: Date().addingTimeInterval(-86400),
                        category: .caches
                    )
                ]
            ),
            ScanResult(
                category: .downloads,
                items: [
                    CleanableItem(
                        name: "DerivedData",
                        path: URL(fileURLWithPath: "/tmp/derived"),
                        size: 1024 * 1024 * 1024 * 2,
                        modificationDate: Date(),
                        category: .downloads
                    )
                ]
            )
        ]

        var body: some View {
            ScanResultsCard(
                results: results,
                onOpenExperience: {}
            )
        }
    }

    return PreviewWrapper()
        .padding()
        .frame(width: 700, height: 500)
}
