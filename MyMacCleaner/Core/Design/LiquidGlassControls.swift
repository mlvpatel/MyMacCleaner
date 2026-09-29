import SwiftUI

// MARK: - Floating Action Button (Backward Compatible)

struct FloatingActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Theme.Typography.size20Semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(color.gradient)
                }
                .modifier(CircleGlassModifier(color: color))
                .shadow(color: color.opacity(0.4), radius: isHovered ? 20 : 12, y: isHovered ? 8 : 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct CircleGlassModifier: ViewModifier {
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(color), in: .circle)
        } else {
            circleFallback(content: content)
        }
        #else
        circleFallback(content: content)
        #endif
    }

    private func circleFallback(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Glass Action Button (Backward Compatible)

struct GlassActionButton: View {
    let title: String
    let icon: String?
    let color: Color
    let action: () -> Void
    var isDisabled: Bool = false

    @State private var isHovered = false
    @State private var isPressed = false

    init(_ title: String, icon: String? = nil, color: Color, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isDisabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(Theme.Typography.size13Medium)
                }
                Text(title)
                    .font(Theme.Typography.size13Semibold)
            }
            .foregroundStyle(isDisabled ? color.opacity(0.3) : color)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(color.opacity(isDisabled ? 0.05 : (isHovered ? 0.2 : 0.12)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(
                        color.opacity(isDisabled ? 0.1 : (isHovered ? 0.5 : 0.3)),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .scaleEffect(isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isDisabled { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Glass Segmented Control (Backward Compatible)

struct GlassSegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Namespace private var segmentNamespace

    var body: some View {
        glassContainerWrapper {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selection = option
                        }
                    } label: {
                        Text(label(option))
                            .font(Theme.Typography.size13Medium)
                            .foregroundStyle(selection == option ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background {
                                if selection == option {
                                    segmentBackground
                                        .matchedGeometryEffect(id: "segment", in: segmentNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.xxs)
            .background(Color.white.opacity(0.05))
            .clipShape(.capsule)
        }
    }

    @ViewBuilder
    private func glassContainerWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content()
            }
        } else {
            content()
                .background(.ultraThinMaterial)
                .clipShape(.capsule)
        }
        #else
        content()
            .background(.ultraThinMaterial)
            .clipShape(.capsule)
        #endif
    }

    @ViewBuilder
    private var segmentBackground: some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(.white.opacity(0.15))
        }
        #else
        Capsule()
            .fill(.white.opacity(0.15))
        #endif
    }
}

// MARK: - Glass Tab Picker (Backward Compatible)

struct GlassTabPicker<T: Hashable>: View {
    let tabs: [T]
    @Binding var selection: T
    let icon: (T) -> String
    let label: (T) -> String
    let accentColor: Color

    @Namespace private var tabNamespace

    init(
        tabs: [T],
        selection: Binding<T>,
        icon: @escaping (T) -> String,
        label: @escaping (T) -> String,
        accentColor: Color = .blue
    ) {
        self.tabs = tabs
        self._selection = selection
        self.icon = icon
        self.label = label
        self.accentColor = accentColor
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(tabs, id: \.self) { tab in
                GlassTabButton(
                    icon: icon(tab),
                    label: label(tab),
                    isSelected: selection == tab,
                    accentColor: accentColor,
                    namespace: tabNamespace
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selection = tab
                    }
                }
            }
        }
        .padding(Theme.Spacing.xxs)
        .modifier(GlassCapsuleModifier())
    }
}

struct GlassTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let accentColor: Color
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxxs) {
                Image(systemName: icon)
                    .font(Theme.Typography.size12Medium)

                Text(label)
                    .font(Theme.Typography.size13Medium)
            }
            .foregroundStyle(isSelected ? .white : (isHovered ? .primary : .secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Spacing.xs)
            .background {
                if isSelected {
                    Capsule()
                        .fill(accentColor.gradient)
                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Glass Search Field (Backward Compatible)

struct GlassSearchField: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.ControlSize.controlIconSize, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.ControlSize.controlFont)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.ControlSize.controlIconSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.ControlSize.horizontalPadding)
        .padding(.vertical, Theme.ControlSize.verticalPadding)
        .frame(height: Theme.ControlSize.toolbarHeight)
        .frame(maxWidth: Theme.ControlSize.searchFieldMaxWidth)
        .modifier(SearchFieldGlassModifier(isFocused: isFocused))
        .scaleEffect(isFocused ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

struct SearchFieldGlassModifier: ViewModifier {
    let isFocused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            content.glassEffect(
                isFocused ? .regular : .clear,
                in: RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius)
            )
        } else {
            searchFieldFallback(content: content)
        }
        #else
        searchFieldFallback(content: content)
        #endif
    }

    private func searchFieldFallback(content: Content) -> some View {
        content
            .background(isFocused ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius)
                    .strokeBorder(.white.opacity(isFocused ? 0.2 : 0.1), lineWidth: 1)
            )
    }
}
