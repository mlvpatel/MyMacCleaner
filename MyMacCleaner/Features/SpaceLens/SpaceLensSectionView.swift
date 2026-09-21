import SwiftUI

// MARK: - Space Lens Section

/// Sidebar destination for Space Lens. Shares the same view model as the Disk Cleaner tab.
struct SpaceLensSectionView: View {
    @ObservedObject var viewModel: SpaceLensViewModel
    @State private var isVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                headerSection
                    .staggeredAnimation(index: 0, isActive: isVisible)

                SpaceLensView(viewModel: viewModel)
                    .staggeredAnimation(index: 1, isActive: isVisible)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.pageTopPadding)
        }
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("navigation.spaceLens"))
                    .font(Theme.Typography.size28Bold)

                Text(L("spaceLens.description"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
