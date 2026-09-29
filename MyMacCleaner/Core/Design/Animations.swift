import SwiftUI

// MARK: - Staggered Animation

struct StaggeredAnimation: ViewModifier {
    let index: Int
    let isActive: Bool
    let baseDelay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 20)
            .animation(
                Theme.Animation.spring.delay(Double(index) * baseDelay),
                value: isActive
            )
    }
}

extension View {
    func staggeredAnimation(index: Int, isActive: Bool, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAnimation(index: index, isActive: isActive, baseDelay: baseDelay))
    }
}

// MARK: - Breathing Animation (for scan button)

struct BreathingAnimation: ViewModifier {
    @State private var isBreathing = false
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double

    init(minScale: CGFloat = 0.98, maxScale: CGFloat = 1.02, duration: Double = 2.0) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isBreathing ? maxScale : minScale)
            .animation(
                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                isBreathing = true
            }
    }
}

extension View {
    func breathingAnimation(minScale: CGFloat = 0.98, maxScale: CGFloat = 1.02, duration: Double = 2.0) -> some View {
        modifier(BreathingAnimation(minScale: minScale, maxScale: maxScale, duration: duration))
    }
}

// MARK: - Loading Dots Animation

struct LoadingDotsView: View {
    @State private var activeIndex = 0
    let dotCount: Int
    let dotSize: CGFloat
    let color: Color

    init(dotCount: Int = 3, dotSize: CGFloat = 8, color: Color = .blue) {
        self.dotCount = dotCount
        self.dotSize = dotSize
        self.color = color
    }

    var body: some View {
        HStack(spacing: dotSize / 2) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(activeIndex == index ? 1.3 : 1.0)
                    .opacity(activeIndex == index ? 1.0 : 0.5)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                withAnimation(Theme.Animation.spring) {
                    activeIndex = (activeIndex + 1) % dotCount
                }
            }
        }
    }
}

// MARK: - Progress Ring Animation

struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color

    @State private var animatedProgress: Double = 0

    init(progress: Double, lineWidth: CGFloat = 8, color: Color = .blue) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(Theme.Animation.slow) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(Theme.Animation.normal) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        LoadingDotsView()

        ProgressRing(progress: 0.7)
            .frame(width: 60, height: 60)

        Text("Breathing")
            .padding()
            .background(.blue)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .breathingAnimation()
    }
    .padding()
    .frame(width: 300, height: 400)
}
