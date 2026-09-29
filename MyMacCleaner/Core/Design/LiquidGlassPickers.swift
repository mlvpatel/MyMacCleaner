import SwiftUI

// MARK: - Glass Control Modifier (Shared styling for Pickers/Toggles)

struct GlassControlModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            content
                .padding(.horizontal, Theme.ControlSize.horizontalPadding)
                .padding(.vertical, Theme.ControlSize.verticalPadding)
                .frame(height: Theme.ControlSize.toolbarHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius))
        } else {
            controlFallback(content: content)
        }
        #else
        controlFallback(content: content)
        #endif
    }

    private func controlFallback(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.ControlSize.horizontalPadding)
            .padding(.vertical, Theme.ControlSize.verticalPadding)
            .frame(height: Theme.ControlSize.toolbarHeight)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    func glassControlStyle() -> some View {
        self.modifier(GlassControlModifier())
    }
}

// MARK: - Glass Toggle (Native Toggle with Glass Styling)

struct GlassToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.ControlSize.controlFont)
                .foregroundStyle(.secondary)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .glassControlStyle()
    }
}

// MARK: - Glass Menu Button (Custom Menu with Glass Styling)

struct GlassMenuButton<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: Theme.Spacing.xxxs) {
                Image(systemName: icon)
                    .font(.system(size: Theme.ControlSize.controlIconSize, weight: .medium))
                Text(title)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.size10Medium)
            }
            .font(Theme.ControlSize.controlFont)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.ControlSize.horizontalPadding)
            .padding(.vertical, Theme.ControlSize.verticalPadding)
            .frame(height: Theme.ControlSize.toolbarHeight)
            .modifier(GlassMenuModifier(isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct GlassMenuModifier: ViewModifier {
    let isHovered: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            content.glassEffect(
                isHovered ? .regular : .clear,
                in: RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius)
            )
        } else {
            menuFallback(content: content)
        }
        #else
        menuFallback(content: content)
        #endif
    }

    private func menuFallback(content: Content) -> some View {
        content
            .background(isHovered ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius)
                    .strokeBorder(.white.opacity(isHovered ? 0.15 : 0.1), lineWidth: 1)
            )
    }
}
