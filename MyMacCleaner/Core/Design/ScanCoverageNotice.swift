import SwiftUI

/// Names the folders a scan could not fully read, so missing access never looks like an empty disk.
/// Denied folders link to Permissions; partly read folders only warn that results may be incomplete.
struct ScanCoverageNotice: View {
    private let deniedText: String?
    private let partialText: String?
    private let droppedText: String?
    let openPermissions: () -> Void

    init(coverage: LegacyScanCoverage, openPermissions: @escaping () -> Void) {
        deniedText = coverage.deniedFolders.isEmpty
            ? nil : LFormat("scan.coverage.denied %@", Self.names(coverage.deniedFolders))
        partialText = coverage.partialFolders.isEmpty
            ? nil : LFormat("scan.coverage.partial %@", Self.names(coverage.partialFolders))
        droppedText = coverage.droppedFindingCount > 0
            ? LFormat("scan.coverage.dropped %lld", coverage.droppedFindingCount) : nil
        self.openPermissions = openPermissions
    }

    /// For a list macOS refused to read in part outside the folder scan, such as browser data.
    init(deniedText: String, openPermissions: @escaping () -> Void) {
        self.deniedText = deniedText
        partialText = nil
        droppedText = nil
        self.openPermissions = openPermissions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let deniedText {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(deniedText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    GlassActionButton(
                        L("scan.coverage.openPermissions"),
                        icon: NavigationSection.permissions.icon,
                        color: NavigationSection.permissions.color,
                        action: openPermissions
                    )
                    .accessibilityIdentifier("scan.coverage.open-permissions")
                }
            }

            if let partialText {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(partialText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let droppedText {
                Text(droppedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(.secondary)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .orange, cornerRadius: Theme.CornerRadius.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.coverage")
    }

    /// Plain English list: the app is English-only, so a locale-aware formatter would mix languages.
    private static func names(_ folders: [ScanCategory]) -> String {
        folders.map(\.localizedName).joined(separator: ", ")
    }
}
