import CleanerCore
import Foundation
import SwiftUI

// MARK: - Performance View

struct PerformanceView: View {
    @ObservedObject var viewModel: PerformanceViewModel
    @State private var isVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                headerSection
                    .staggeredAnimation(index: 0, isActive: isVisible)
                pressureSection
                    .staggeredAnimation(index: 1, isActive: isVisible)
                memoryBreakdownSection
                    .staggeredAnimation(index: 2, isActive: isVisible)
                processSection
                    .staggeredAnimation(index: 3, isActive: isVisible)
                guidanceSection
                    .staggeredAnimation(index: 4, isActive: isVisible)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.pageTopPadding)
        }
        .onAppear {
            withAnimation(Theme.Animation.springSmooth) {
                isVisible = true
            }
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(L("navigation.performance"))
                    .font(Theme.Typography.size28Bold)
                Text(L("performance.subtitle"))
                    .font(Theme.Typography.size13)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(L("performance.cpu"))
                    .font(Theme.Typography.size11)
                    .foregroundStyle(.secondary)
                Text("\(Int(viewModel.cpuUsage))%")
                    .font(Theme.Typography.size22Semibold.monospacedDigit())
                    .foregroundStyle(cpuColor)
                ProgressView(value: viewModel.cpuUsage, total: 100)
                    .progressViewStyle(.linear)
                    .tint(cpuColor)
                    .frame(width: 100)
            }
            .padding(Theme.Spacing.md)
            .glassCard(cornerRadius: Theme.CornerRadius.medium)
        }
    }

    private var pressureSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(L("performance.memory.pressure"))
                    .font(Theme.Typography.headline)
                Spacer()
                Button(L("performance.refresh")) {
                    viewModel.refreshMemoryCoach()
                }
                .buttonStyle(.bordered)
            }

            Text(L(viewModel.presentation.explanation.pressureKey.rawValue))
                .font(Theme.Typography.size18Semibold)
                .foregroundStyle(pressureColor)
            Text(pressureTimestamp)
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(L(viewModel.presentation.explanation.completenessKey.rawValue))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .glassCard()
    }

    private var memoryBreakdownSection: some View {
        let fields = viewModel.presentation.fields
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("performance.memory.breakdown"))
                .font(Theme.Typography.headline)

            HStack(spacing: Theme.Spacing.md) {
                memoryBreakdownCard(title: L("performance.memory.physicalMemory"), value: fieldValue(fields.physicalMemory), color: .blue)
                memoryBreakdownCard(title: L("performance.memory.active"), value: fieldValue(fields.activeMemory), color: .orange)
                memoryBreakdownCard(title: L("performance.memory.wired"), value: fieldValue(fields.wiredMemory), color: .purple)
                memoryBreakdownCard(title: L("performance.memory.compressed"), value: fieldValue(fields.compressedMemory), color: .green)
            }

            HStack(spacing: Theme.Spacing.md) {
                memoryBreakdownCard(title: L("performance.memory.cached"), value: fieldValue(fields.inactiveMemory), color: .teal)
                memoryBreakdownCard(title: L("performance.memory.purgeable"), value: fieldValue(fields.purgeableMemory), color: .indigo)
                memoryBreakdownCard(title: L("performance.memory.swap"), value: swapValue(fields.swapUsed, fields.swapTotal), color: .pink)
            }

            Text(L(viewModel.presentation.explanation.cacheKey.rawValue))
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L("performance.processes.title"))
                .font(Theme.Typography.headline)

            if viewModel.presentation.processes.isEmpty {
                Text(L("performance.processes.empty"))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.presentation.processes.enumerated()), id: \.offset) { entry in
                    ProcessRow(rank: entry.offset + 1, process: entry.element)
                }
            }

            ForEach(viewModel.presentation.processIssueKeys, id: \.rawValue) { key in
                Text(L(key.rawValue))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L("performance.processes.observational"))
                .font(Theme.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(L("performance.guidance.title"))
                .font(Theme.Typography.headline)
            Text(L("performance.guidance.body"))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)

            ForEach(viewModel.presentation.explanation.suggestionKeys, id: \.rawValue) { key in
                Text(L(key.rawValue))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private var cpuColor: Color {
        viewModel.cpuUsage > 80 ? .red : viewModel.cpuUsage > 50 ? .orange : .green
    }

    private var pressureColor: Color {
        switch viewModel.presentation.pressure {
        case .observed(.normal, _):
            .green
        case .observed(.warning, _):
            .orange
        case .observed(.critical, _):
            .red
        case .stale, .unavailableNoFreshEvent:
            .secondary
        }
    }

    private var pressureTimestamp: String {
        switch viewModel.presentation.pressure {
        case let .observed(_, observedAt), let .stale(_, observedAt):
            observedTimestamp(observedAt)
        case .unavailableNoFreshEvent:
            L("performance.memory.unavailable")
        }
    }

    private func memoryBreakdownCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(value)
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private func fieldValue(_ value: MemoryCoachValuePresentation) -> String {
        switch value {
        case let .observed(bytes, observedAt):
            "\(byteCount(bytes)) · \(observedTimestamp(observedAt))"
        case .unavailable:
            L("performance.memory.unavailable")
        }
    }

    private func swapValue(
        _ used: MemoryCoachValuePresentation,
        _ total: MemoryCoachValuePresentation
    ) -> String {
        switch (used, total) {
        case let (.observed(usedBytes, usedAt), .observed(totalBytes, totalAt)):
            let values = LFormat("performance.memory.swapOf %@ %@", byteCount(usedBytes), byteCount(totalBytes))
            return "\(values) · \(observedTimestamp(usedAt)) · \(observedTimestamp(totalAt))"
        case (.unavailable, _), (_, .unavailable):
            return L("performance.memory.unavailable")
        }
    }

    private func observedTimestamp(_ reading: ClockReading) -> String {
        let seconds = Double(reading.wallClockInstant.unixNanoseconds) / 1_000_000_000
        let date = Date(timeIntervalSince1970: seconds)
        return LFormat("performance.memory.observedAt %@", date.formatted(date: .abbreviated, time: .standard))
    }

    private func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

#Preview {
    PerformanceView(viewModel: PerformanceViewModel())
        .frame(width: 800, height: 700)
}
