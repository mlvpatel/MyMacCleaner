import SwiftUI
import Combine

// MARK: - Liquid Glass Design System
// Native .glassEffect() on macOS 26+, .ultraThinMaterial fallback on older versions
// CI_BUILD flag disables macOS 26 APIs for compatibility with older SDKs

// MARK: - Glass Card Modifiers

extension View {
    /// Standard glass card with rounded corners
    @ViewBuilder
    func glassCard() -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        } else {
            glassCardFallback(cornerRadius: Theme.CornerRadius.large)
        }
        #else
        glassCardFallback(cornerRadius: Theme.CornerRadius.large)
        #endif
    }

    private func glassCardFallback(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
    }

    /// Glass card with custom corner radius
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            glassCardFallback(cornerRadius: cornerRadius)
        }
        #else
        glassCardFallback(cornerRadius: cornerRadius)
        #endif
    }

    /// Prominent glass card for important elements
    @ViewBuilder
    func glassCardProminent(cornerRadius: CGFloat = 16) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        } else {
            glassCardProminentFallback(cornerRadius: cornerRadius)
        }
        #else
        glassCardProminentFallback(cornerRadius: cornerRadius)
        #endif
    }

    private func glassCardProminentFallback(cornerRadius: CGFloat) -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }

    /// Subtle glass card - uses clear variant for high transparency
    @ViewBuilder
    func glassCardSubtle(cornerRadius: CGFloat = 12) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self.glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            glassCardSubtleFallback(cornerRadius: cornerRadius)
        }
        #else
        glassCardSubtleFallback(cornerRadius: cornerRadius)
        #endif
    }

    private func glassCardSubtleFallback(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Pill-shaped glass (for tags, buttons)
    @ViewBuilder
    func glassPill() -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            glassPillFallback()
        }
        #else
        glassPillFallback()
        #endif
    }

    private func glassPillFallback() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(.capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    /// Circle glass effect
    @ViewBuilder
    func glassCircle() -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            glassCircleFallback()
        }
        #else
        glassCircleFallback()
        #endif
    }

    private func glassCircleFallback() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(.circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    /// Glass effect with tint color
    @ViewBuilder
    func glassCard(tint: Color, cornerRadius: CGFloat = 16) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            glassCardTintFallback(tint: tint, cornerRadius: cornerRadius)
        }
        #else
        glassCardTintFallback(tint: tint, cornerRadius: cornerRadius)
        #endif
    }

    private func glassCardTintFallback(tint: Color, cornerRadius: CGFloat) -> some View {
        self
            .background(tint.opacity(0.1))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Interactive Effects

extension View {
    /// Applies hover effect with scale
    func hoverEffect(isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }

    /// Applies press effect
    func pressEffect(isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
    }

    /// Floating effect with shadow on hover
    func floatingEffect(isHovered: Bool) -> some View {
        self
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.2 : 0.1),
                radius: isHovered ? 20 : 10,
                y: isHovered ? 8 : 4
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}

// MARK: - Glass Capsule Modifier (Reusable)

struct GlassCapsuleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            capsuleFallback(content: content)
        }
        #else
        capsuleFallback(content: content)
        #endif
    }

    private func capsuleFallback(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(.capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Glass Button Style (Backward Compatible)

struct LiquidGlassButtonStyle: ButtonStyle {
    enum Variant {
        case regular
        case prominent
        case tinted(Color)
    }

    let variant: Variant
    let cornerRadius: CGFloat

    init(_ variant: Variant = .regular, cornerRadius: CGFloat = 12) {
        self.variant = variant
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 10)
            .background {
                switch variant {
                case .prominent:
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                default:
                    Color.clear
                }
            }
            .modifier(GlassEffectModifier(variant: variant, cornerRadius: cornerRadius))
            .foregroundStyle(foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .regular: return .primary
        case .prominent: return .white
        case .tinted(let color): return color
        }
    }
}

// Helper modifier for button glass effect
struct GlassEffectModifier: ViewModifier {
    let variant: LiquidGlassButtonStyle.Variant
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        #if !CI_BUILD
        if #available(macOS 26, *) {
            content.glassEffect(glassVariantMacOS26, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            fallbackContent(content: content)
        }
        #else
        fallbackContent(content: content)
        #endif
    }

    private func fallbackContent(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
    }

    #if !CI_BUILD
    @available(macOS 26, *)
    private var glassVariantMacOS26: Glass {
        switch variant {
        case .regular, .prominent:
            return .regular
        case .tinted(let color):
            return .regular.tint(color)
        }
    }
    #endif
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle(.regular) }
    static var liquidGlassProminent: LiquidGlassButtonStyle { LiquidGlassButtonStyle(.prominent) }
    static func liquidGlassTinted(_ color: Color) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(.tinted(color))
    }
}

// MARK: - Preview

#Preview("Liquid Glass Components") {
    ZStack {
        LinearGradient(
            colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: Theme.Spacing.xl) {
            Text("Glass Card")
                .padding()
                .glassCard()

            Text("Prominent Glass")
                .padding()
                .glassCardProminent()

            Text("Glass Pill")
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .glassPill()

            HStack(spacing: Theme.Spacing.sm) {
                Button("Glass") {}
                    .buttonStyle(.liquidGlass)

                Button("Prominent") {}
                    .buttonStyle(.liquidGlassProminent)

                Button("Tinted") {}
                    .buttonStyle(.liquidGlassTinted(.green))
            }

            GlassSearchField(text: .constant(""), placeholder: "Search...")
                .frame(width: 300)

            GlassSegmentedControl(
                options: ["All", "Active", "Inactive"],
                selection: .constant("All"),
                label: { $0 }
            )

            FloatingActionButton(icon: "plus", color: .blue) {}
        }
        .padding()
    }
    .frame(width: 500, height: 600)
}
