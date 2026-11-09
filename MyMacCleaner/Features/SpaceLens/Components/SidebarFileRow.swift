import SwiftUI

// MARK: - Sidebar File Row

/// One item of the current folder. The list is the keyboard and VoiceOver equivalent
/// of the bubble chart, so each row is a button that names the item and its size.
struct SidebarFileRow: View {
    let node: FileNode
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    let onInfo: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Show in Finder button
            Button(action: onInfo) {
                Image(systemName: "folder")
                    .font(Theme.Typography.size12)
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .help(L("common.showInFinder"))
            .accessibilityLabel(L("common.showInFinder"))

            Button(action: onTap) {
                HStack(spacing: Theme.Spacing.sm) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .fill(node.color.opacity(0.15))
                            .frame(width: 30, height: 30)

                        Image(systemName: node.icon)
                            .font(Theme.Typography.size13)
                            .foregroundStyle(node.color)
                    }

                    // Name
                    Text(node.name)
                        .font(Theme.Typography.size13)
                        .lineLimit(1)

                    Spacer()

                    // Size
                    Text(node.formattedSize)
                        .font(Theme.Typography.size12.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .accessibilityLabel(node.name)
            .accessibilityValue(node.formattedSize)
            .accessibilityHint(node.isDirectory ? L("spaceLens.row.openHint") : "")
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.surfaceMedium)
            }
        }
        .onHover(perform: onHover)
        // Keyboard focus shows the same details as a pointer hover.
        .onChange(of: isFocused) { _, focused in onHover(focused) }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
