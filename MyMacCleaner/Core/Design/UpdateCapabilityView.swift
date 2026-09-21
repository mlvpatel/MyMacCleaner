import SwiftUI

// MARK: - Update Capability View

/// Visible, non-actionable update status. It has no buttons, links, or network access.
struct UpdateCapabilityView: View {
    let capability: UpdateCapability

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label(L(capability.titleKey), systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text(L(capability.messageKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("update.capability")
    }
}
