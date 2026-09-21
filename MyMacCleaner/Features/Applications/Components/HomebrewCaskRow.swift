import SwiftUI

// MARK: - Homebrew Cask Row

struct HomebrewCaskRow: View {
    let cask: HomebrewCask

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "shippingbox.fill")
                    .font(Theme.Typography.size18)
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(cask.displayName)
                        .font(Theme.Typography.subheadline.weight(.semibold))

                }

                HStack(spacing: Theme.Spacing.xs) {
                    if let installedVersion = cask.installedVersion, !installedVersion.isEmpty {
                        Text("v\(installedVersion)")
                            .foregroundStyle(.secondary)
                    } else if !cask.version.isEmpty {
                        Text("v\(cask.version)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(Theme.Typography.caption)

                if let description = cask.description {
                    Text(description)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: Theme.Spacing.sm) {
                if let homepage = cask.homepage {
                    Link(destination: homepage) {
                        Image(systemName: "globe")
                            .font(Theme.Typography.size14)
                            .foregroundStyle(.secondary)
                    }
                }

            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.white.opacity(isHovered ? 0.05 : 0))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .onHover { isHovered = $0 }
    }
}
