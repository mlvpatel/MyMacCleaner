import SwiftUI

// MARK: - Permission Prompt View

struct PermissionPromptView: View {
    @ObservedObject var permissionsService: PermissionsService
    let onDismiss: () -> Void
    let onContinueWithoutPermission: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Icon
            iconSection

            // Content
            contentSection

            // Features list
            featuresSection

            // Buttons
            buttonsSection
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 500)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.permission.sheet")
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 120, height: 120)
                .blur(radius: 20)

            // Icon container
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.blue.opacity(0.5), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.shield.fill")
                    .font(Theme.Typography.size32Medium)
                    .foregroundStyle(.blue.gradient)
            }
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(L("permissions.fda.title"))
                .font(Theme.Typography.title2)

            Text(L("permissions.fda.description"))
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L("permissions.fda.features"))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.tertiary)

            ForEach(PermissionsService.fullDiskAccessInfo.localizedFeatures, id: \.self) { feature in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Text(feature)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Color.blue.opacity(0.05))
        )
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Grant permission button
            GlassActionButton(
                L("permissions.fda.openSettings"),
                icon: "gear",
                color: .blue
            ) {
                permissionsService.openFullDiskAccessSettings()
            }

            // Skip button
            Button(action: onContinueWithoutPermission) {
                Text(L("permissions.fda.limitedScan"))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.plain)

            // Said before the scan starts, so the macOS folder prompts are expected.
            Text(L("permissions.fda.limitedScan.folders"))
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Dismiss button for later; Escape closes the sheet the same way
            Button(action: onDismiss) {
                Text(L("permissions.fda.later"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("home.permission.later")
        }
    }
}

// MARK: - Preview

#Preview("Permission Prompt") {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        PermissionPromptView(
            permissionsService: PermissionsService.shared,
            onDismiss: {},
            onContinueWithoutPermission: {}
        )
    }
    .frame(width: 600, height: 700)
}
