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
    let onLearnWhy: (() -> Void)?
    let onDismiss: () -> Void

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        message: String,
        type: ToastType,
        safetyNotice: SafetyNoticeState? = nil,
        onLearnWhy: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.type = type
        self.safetyNotice = safetyNotice
        self.onLearnWhy = onLearnWhy
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

                    if let onLearnWhy {
                        Button(notice.actionTitle, action: onLearnWhy)
                            .buttonStyle(.link)
                            .font(Theme.Typography.caption.weight(.medium))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(notice.accessibilityIdentifier)
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
            .accessibilityLabel(L("common.dismiss"))
            .help(L("common.dismiss"))
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
        .offset(y: isVisible || reduceMotion ? 0 : -20)
        .onAppear {
            withAnimation(Theme.Animation.motion(Theme.Animation.spring, reduce: reduceMotion)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Toast Overlay

/// A screen's toast, pinned to the top. "Learn why" clears the notice before it navigates.
struct ToastOverlay: View {
    @ObservedObject var presenter: ToastPresenter
    var onLearnWhy: (() -> Void)?

    var body: some View {
        VStack {
            if let toast = presenter.current {
                ToastView(
                    message: toast.message,
                    type: toast.type,
                    safetyNotice: toast.safetyNotice,
                    onLearnWhy: learnWhyAction,
                    onDismiss: presenter.dismiss
                )
                .id(toast.id)
                .padding(.top, Theme.Spacing.lg)
                .motionTransition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(Theme.Animation.spring, value: presenter.current?.id)
    }

    private var learnWhyAction: (() -> Void)? {
        guard let onLearnWhy else { return nil }
        return {
            presenter.dismiss()
            onLearnWhy()
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
