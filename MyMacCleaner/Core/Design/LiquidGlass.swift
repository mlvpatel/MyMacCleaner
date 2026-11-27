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
        modifier(GlassFallback(shape: RoundedRectangle(cornerRadius: cornerRadius)))
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
        modifier(GlassFallback(shape: RoundedRectangle(cornerRadius: cornerRadius), material: .regularMaterial))
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
        modifier(GlassFallback(shape: RoundedRectangle(cornerRadius: cornerRadius), outline: nil))
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
        modifier(GlassFallback(shape: Capsule()))
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
            .modifier(GlassFallback(shape: RoundedRectangle(cornerRadius: cornerRadius), outline: tint.opacity(0.3)))
    }
}

// MARK: - Glass Fallback (macOS 14-15)

/// The stand-in for Liquid Glass before macOS 26: a material behind the content and a
/// separator-colour outline, both readable in Light and Dark. Reduce Transparency swaps the
/// material for the opaque control background; Increase Contrast thickens the outline.
struct GlassFallback<S: InsettableShape>: ViewModifier {
    let shape: S
    /// nil draws no fill (the unfocused search field, unhovered menus).
    var material: Material? = .ultraThinMaterial
    /// nil draws no outline.
    var outline: Color? = Theme.Colors.glassStroke

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .clipShape(shape)
            .overlay {
                if let outline {
                    shape.strokeBorder(outline, lineWidth: contrast == .increased ? 1.5 : 1)
                }
            }
    }

    private var fill: AnyShapeStyle {
        guard let material else { return AnyShapeStyle(Color.clear) }
        return reduceTransparency ? AnyShapeStyle(Theme.Colors.secondaryBackground) : AnyShapeStyle(material)
    }
}

// MARK: - Interactive Effects

extension View {
    /// Applies hover effect with scale (none with Reduce Motion)
    func hoverEffect(isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        modifier(HoverEffect(isHovered: isHovered, scale: scale))
    }
}

private struct HoverEffect: ViewModifier {
    let isHovered: Bool
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? scale : 1.0)
            .animation(Theme.Animation.motion(.spring(response: 0.3, dampingFraction: 0.7), reduce: reduceMotion), value: isHovered)
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
        content.modifier(GlassFallback(shape: Capsule()))
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

            GlassSearchField(text: .constant(""), placeholder: "Search...")
                .frame(width: 300)

            GlassSegmentedControl(
                options: ["All", "Active", "Inactive"],
                selection: .constant("All"),
                label: { $0 }
            )
        }
        .padding()
    }
    .frame(width: 500, height: 600)
}
