import SwiftUI

// MARK: - Shared Toast Type

/// Shared toast notification type used across all ViewModels
/// Consolidates the previously duplicated ToastType enums
enum ToastType: Sendable {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let type: ToastType
    let safetyNotice: SafetyNoticeState?
    let onDismiss: () -> Void

    @State private var isVisible = false

    init(
        message: String,
        type: ToastType,
        safetyNotice: SafetyNoticeState? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.type = type
        self.safetyNotice = safetyNotice
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundStyle(type.color)

            if let notice = safetyNotice {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(notice.title)
                        .font(Theme.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(notice.message)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(.secondary)

                    Text(notice.actionTitle)
                        .font(Theme.Typography.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(notice.accessibilityIdentifier)
                .accessibilityHint(notice.actionTitle)
            } else {
                Text(message)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(type.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isVisible = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Toast Success") {
    VStack {
        Spacer()
        ToastView(
            message: "Cleaned 1.5 GB successfully!",
            type: .success,
            onDismiss: {}
        )
        Spacer()
    }
    .frame(width: 500, height: 300)
    .background(Color.black.opacity(0.8))
}

#Preview("Toast Error") {
    VStack {
        Spacer()
        ToastView(
            message: "Failed to clean items",
            type: .error,
            onDismiss: {}
        )
        Spacer()
    }
    .frame(width: 500, height: 300)
    .background(Color.black.opacity(0.8))
}
