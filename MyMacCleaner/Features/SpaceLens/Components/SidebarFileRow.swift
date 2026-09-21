import SwiftUI

// MARK: - Sidebar File Row

struct SidebarFileRow: View {
    let node: FileNode
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Info button
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(Theme.Typography.size12)
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover(perform: onHover)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
