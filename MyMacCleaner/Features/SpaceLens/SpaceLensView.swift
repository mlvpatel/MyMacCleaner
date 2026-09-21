import SwiftUI

// MARK: - Space Lens View

struct SpaceLensView: View {
    @ObservedObject var viewModel: SpaceLensViewModel
    @State private var isVisible = false

    var body: some View {
        ZStack {
            if viewModel.rootNode == nil && !viewModel.isScanning {
                startScanSection
                    .glassCard()
            } else if let currentNode = viewModel.currentNode {
                mainContent(currentNode)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                    .glassCard()
            }

            // Scanning overlay
            if viewModel.isScanning {
                ScanningOverlay(
                    progress: viewModel.scanProgress,
                    category: viewModel.currentPath,
                    accentColor: .blue,
                    onCancel: viewModel.cancelScan
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.Animation.springSmooth, value: viewModel.isScanning)
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
        }
        .onDisappear {
            viewModel.cancelScan()
        }
    }

    // MARK: - Main Content

    private func mainContent(_ currentNode: FileNode) -> some View {
        HStack(spacing: 0) {
            // Sidebar with file list
            sidebarView(currentNode)
                .frame(width: 280)

            Divider()

            // Bubble visualization
            VStack(spacing: 0) {
                // Header
                headerBar(currentNode)

                // Bubbles
                GeometryReader { geometry in
                    BubblePackingView(
                        nodes: viewModel.currentChildren,
                        parentSize: currentNode.size,
                        size: geometry.size,
                        onSelect: { node in
                            if node.isDirectory {
                                viewModel.navigateTo(node)
                            }
                        },
                        onHover: { viewModel.hoverNode($0) },
                        highlightedNodeId: viewModel.hoveredNode?.id
                    )
                }
                .padding(Theme.Spacing.md)
                .id("\(viewModel.sizeFilter.rawValue)-\(viewModel.ageFilter.rawValue)") // Force rebuild on filter change

                // Bottom bar
                bottomBar
            }
        }
    }

    // MARK: - Sidebar

    private func sidebarView(_ currentNode: FileNode) -> some View {
        VStack(spacing: 0) {
            // Current folder info
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "internaldrive.fill")
                        .font(Theme.Typography.size22)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(currentNode.name)
                        .font(Theme.Typography.size15Semibold)
                        .lineLimit(1)

                    Text(LFormat("spaceLens.sizeItems %@ %lld", currentNode.formattedSize, currentNode.children.count))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Color.white.opacity(0.03))

            // File list
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.tiny) {
                    ForEach(currentNode.children.sorted(by: { $0.size > $1.size })) { child in
                        SidebarFileRow(
                            node: child,
                            isHovered: viewModel.hoveredNode?.id == child.id,
                            onTap: {
                                if child.isDirectory {
                                    viewModel.navigateTo(child)
                                }
                            },
                            onHover: { hovering in
                                viewModel.hoverNode(hovering ? child : nil)
                            },
                            onInfo: {
                                viewModel.revealInFinder(child)
                            }
                        )
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }

    // MARK: - Header Bar

    private func headerBar(_ currentNode: FileNode) -> some View {
        VStack(spacing: 0) {
            // Navigation row
            HStack {
                // Navigation button
                Button(action: viewModel.navigateUp) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.size14Semibold)
                        .foregroundStyle(viewModel.navigationStack.count > 1 ? .primary : .tertiary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.navigationStack.count <= 1)

                Spacer()

                // Breadcrumb
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Button(action: { viewModel.navigateTo(node) }) {
                            HStack(spacing: Theme.Spacing.xxs) {
                                if index == 0 {
                                    Image(systemName: "internaldrive.fill")
                                        .font(.caption)
                                }
                                Text(node.name)
                                    .font(Theme.Typography.caption)
                            }
                            .foregroundStyle(index == viewModel.breadcrumbs.count - 1 ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Rescan button
                Button(action: viewModel.scanHomeDirectory) {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.Typography.size12)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)

            // Filter row
            HStack(spacing: Theme.Spacing.md) {
                // Size filter
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(Theme.Typography.size10)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $viewModel.sizeFilter) {
                        ForEach(SizeFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedName).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(viewModel.sizeFilter != .all ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                // Age filter
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(Theme.Typography.size10)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $viewModel.ageFilter) {
                        ForEach(AgeFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedName).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(viewModel.ageFilter != .all ? Color.orange.opacity(0.15) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                // Clear filters button
                if viewModel.hasActiveFilters {
                    Button(action: viewModel.clearFilters) {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: "xmark.circle.fill")
                                .font(Theme.Typography.size10)
                            Text(L("spaceLens.filter.clear"))
                                .font(Theme.Typography.size11)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if viewModel.isTruncated {
                    Text(LFormat("spaceLens.truncated %lld", Int64(SpaceLensScanLimits.maxEntries)))
                        .font(Theme.Typography.size11)
                        .foregroundStyle(.orange)
                }

                // Filter stats
                if viewModel.hasActiveFilters {
                    Text(LFormat("spaceLens.filter.showing %lld %lld", Int64(viewModel.filteredCount), Int64(viewModel.totalCount)))
                        .font(Theme.Typography.size11)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.white.opacity(0.02))
        }
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if let hovered = viewModel.hoveredNode {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: hovered.icon)
                        .foregroundStyle(hovered.color)

                    Text(hovered.name)
                        .font(Theme.Typography.subheadline)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(hovered.formattedSize)
                        .font(Theme.Typography.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let parent = viewModel.currentNode, parent.size > 0 {
                        Text("(\(Int(Double(hovered.size) / Double(parent.size) * 100))%)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Show last access date for files
                    if !hovered.isDirectory, let accessStr = hovered.formattedLastAccess {
                        Text("·")
                            .foregroundStyle(.tertiary)

                        HStack(spacing: Theme.Spacing.tiny) {
                            Image(systemName: "clock")
                                .font(Theme.Typography.size10)
                            Text(accessStr)
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L("spaceLens.hoverHint"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Legend
            HStack(spacing: Theme.Spacing.md) {
                legendItem(color: .blue, label: L("spaceLens.legend.folders"))
                legendItem(color: .purple, label: L("spaceLens.legend.apps"))
                legendItem(color: .pink, label: L("spaceLens.legend.videos"))
                legendItem(color: .green, label: L("spaceLens.legend.audio"))
                legendItem(color: .cyan, label: L("spaceLens.legend.images"))
                legendItem(color: .gray, label: L("spaceLens.legend.other"))
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color.white.opacity(0.03))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Start Scan Section

    private var startScanSection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)

                    Image(systemName: "circle.hexagongrid.fill")
                        .font(Theme.Typography.size32Medium)
                        .foregroundStyle(.blue.gradient)
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text(L("spaceLens.title"))
                    .font(Theme.Typography.title2)

                Text(L("spaceLens.description"))
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            GlassActionButton(
                L("spaceLens.scanHome"),
                icon: "house.fill",
                color: .blue
            ) {
                viewModel.scanHomeDirectory()
            }

            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Preview

#Preview {
    SpaceLensView(viewModel: SpaceLensViewModel())
        .frame(width: 1000, height: 700)
}
