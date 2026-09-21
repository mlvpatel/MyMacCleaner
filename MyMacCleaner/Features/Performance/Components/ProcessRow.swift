import CleanerCore
import Foundation
import SwiftUI

// MARK: - Process Row

struct ProcessRow: View {
    let rank: Int
    let process: MemoryCoachProcessRow

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(rank)")
                .font(Theme.Typography.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            Text(process.label.value)
                .font(Theme.Typography.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Theme.Spacing.tiny) {
                Text(LFormat("performance.processes.pid %@", String(process.pid)))
                Text(LFormat("performance.processes.resident %@", byteCount(process.residentBytes)))
                Text(L(process.contextKey.rawValue))
                    .foregroundStyle(.tertiary)
            }
            .font(Theme.Typography.caption.monospacedDigit())
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
