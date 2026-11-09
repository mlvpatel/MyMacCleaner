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
            .modifier(GlassFallback(shape: RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius)))
    }
}

extension View {
    func glassControlStyle() -> some View {
        self.modifier(GlassControlModifier())
    }
}

// MARK: - Glass Toggle (Native Toggle with Glass Styling)

/// The title is the switch's own label, so VoiceOver names the switch.
struct GlassToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Theme.ControlSize.controlFont)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
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
        content.modifier(GlassFallback(
            shape: RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius),
            material: isHovered ? .ultraThinMaterial : nil
        ))
    }
}
