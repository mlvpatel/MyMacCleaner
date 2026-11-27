import SwiftUI

/// Takes the place of a list whose search hides every row, so the list never looks blank,
/// and offers a way back to the full list.
struct NoSearchMatchesView: View {
    let query: String
    var clearTitle = L("common.clearSearch")
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.size48)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(query.isEmpty ? L("common.noMatches") : LFormat("common.noMatchesFor %@", query))
                .font(Theme.Typography.headline)
                .multilineTextAlignment(.center)

            Button(clearTitle, action: onClear)
                .buttonStyle(.plain)
                .font(Theme.Typography.size13Medium)
                .foregroundStyle(.secondary)
                .focusRing(cornerRadius: Theme.CornerRadius.small)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxl)
        .accessibilityIdentifier("search.no-matches")
    }
}
