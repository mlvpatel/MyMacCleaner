import SwiftUI

// MARK: - Focus Ring

extension View {
    /// The one focus ring for custom buttons and rows: a 2 pt stroke in the system keyboard-focus
    /// colour that follows the control's corner radius. Apply it to the Button.
    func focusRing(cornerRadius: CGFloat = Theme.CornerRadius.medium) -> some View {
        modifier(FocusRing(cornerRadius: cornerRadius))
    }

    /// Makes a tap-only view a plain Button with the focus ring, so the keyboard, Full Keyboard
    /// Access, Switch Control and VoiceOver can press it. The view must not contain other buttons.
    func pressable(cornerRadius: CGFloat = Theme.CornerRadius.large, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing(cornerRadius: cornerRadius)
    }

    /// A pressable disclosure header that reports whether its content is expanded.
    func expandButton(isExpanded: Bool, cornerRadius: CGFloat = Theme.CornerRadius.large, action: @escaping () -> Void) -> some View {
        pressable(cornerRadius: cornerRadius, action: action)
            .accessibilityValue(L(isExpanded ? "common.expanded" : "common.collapsed"))
    }
}

private struct FocusRing: ViewModifier {
    let cornerRadius: CGFloat

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Glass Press Style

/// Hover and press scale for the custom glass buttons. Press comes from `configuration.isPressed`,
/// not a drag gesture, so it follows the button's own press handling; no scale with Reduce Motion.
struct GlassPressStyle: ButtonStyle {
    let isHovered: Bool
    var hoverScale: CGFloat = 1.02
    var pressedScale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(isPressed: configuration.isPressed))
            .animation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.7), reduce: reduceMotion), value: isHovered)
            .animation(Theme.Animation.motion(.spring(response: 0.2, dampingFraction: 0.7), reduce: reduceMotion), value: configuration.isPressed)
    }

    private func scale(isPressed: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        if isPressed { return pressedScale }
        return isHovered ? hoverScale : 1
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
        .buttonStyle(GlassPressStyle(isHovered: isHovered))
        .focusRing(cornerRadius: Theme.CornerRadius.medium)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Glass Segmented Control (Backward Compatible)

struct GlassSegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Namespace private var segmentNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        glassContainerWrapper {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.7), reduce: reduceMotion)) {
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
                    .focusRing(cornerRadius: Theme.CornerRadius.pill)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(Theme.Spacing.xxs)
            .background(Theme.Colors.surfaceLight)
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
                .modifier(GlassFallback(shape: Capsule(), outline: nil))
        }
        #else
        content()
            .modifier(GlassFallback(shape: Capsule(), outline: nil))
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
                .fill(Theme.Colors.surfaceHover)
        }
        #else
        Capsule()
            .fill(Theme.Colors.surfaceHover)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    withAnimation(Theme.Animation.motion(.spring(response: 0.35, dampingFraction: 0.7), reduce: reduceMotion)) {
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
        .focusRing(cornerRadius: Theme.CornerRadius.pill)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = $0 }
    }
}

// MARK: - Glass Search Field (Backward Compatible)

struct GlassSearchField: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .scaleEffect(isFocused && !reduceMotion ? 1.01 : 1.0)
        .animation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.7), reduce: reduceMotion), value: isFocused)
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
        content.modifier(GlassFallback(
            shape: RoundedRectangle(cornerRadius: Theme.ControlSize.controlRadius),
            material: isFocused ? .ultraThinMaterial : nil
        ))
    }
}
