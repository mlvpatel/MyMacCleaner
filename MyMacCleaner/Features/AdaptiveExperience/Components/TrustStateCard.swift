import SwiftUI

struct TrustStateCard: View {
    let title: String
    let detail: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.headline)
            Text(detail)
                .font(Theme.Typography.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

struct ProtectedDataNotice: View {
    let titleKey: String
    let messageKey: String
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(L(titleKey))
                .font(Theme.Typography.headline)
            Text(L(messageKey))
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(noticeBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(noticeBorder, lineWidth: contrast == .increased || differentiateWithoutColor ? 1.5 : 0)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("adaptive.protected.notice")
    }

    private var noticeBackground: Color {
        contrast == .increased ? Color.orange.opacity(0.28) : Color.orange.opacity(0.12)
    }

    private var noticeBorder: Color {
        contrast == .increased || differentiateWithoutColor ? Color.orange : Color.clear
    }
}

struct DeveloperCapabilityCard: View {
    let facts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(L("adaptive.developer.title"))
                .font(Theme.Typography.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(facts, id: \.self) { fact in
                Text(fact)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("developer.inventory")
    }
}
