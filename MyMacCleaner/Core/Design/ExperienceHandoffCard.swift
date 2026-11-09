import SwiftUI

/// Closes every read-only inventory screen: it says the list cannot change anything and routes
/// to the Adaptive Experience, the only place where the app can move a file (to the Trash).
struct ExperienceHandoffCard: View {
    let openExperience: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: NavigationSection.adaptiveExperience.icon)
                .font(Theme.Typography.size20Medium)
                .foregroundStyle(NavigationSection.adaptiveExperience.color)
                .accessibilityHidden(true)

            Text(L("legacy.handoff.message"))
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            GlassActionButton(
                L("legacy.handoff.open"),
                icon: "arrow.right.circle.fill",
                color: NavigationSection.adaptiveExperience.color,
                action: openExperience
            )
            .accessibilityIdentifier("legacy.open-experience")
        }
        .padding(Theme.Spacing.lg)
        .glassCard()
    }
}
