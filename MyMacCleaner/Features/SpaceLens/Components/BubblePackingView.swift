import AppKit
import SwiftUI

// MARK: - Bubble Packing View using AppKit for proper hit testing

struct BubblePackingView: NSViewRepresentable {
    let nodes: [FileNode]
    let parentSize: Int64
    let size: CGSize
    let onSelect: (FileNode) -> Void
    let onHover: (FileNode?) -> Void
    let highlightedNodeId: UUID?

    func makeNSView(context: Context) -> BubbleContainerView {
        let view = BubbleContainerView()
        view.onSelect = onSelect
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: BubbleContainerView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onHover = onHover
        nsView.highlightedNodeId = highlightedNodeId
        nsView.updateBubbles(nodes: nodes, parentSize: parentSize)
    }
}

// MARK: - AppKit Container View

class BubbleContainerView: NSView {
    var onSelect: ((FileNode) -> Void)?
    var onHover: ((FileNode?) -> Void)?
    var highlightedNodeId: UUID?

    private var bubbleViews: [UUID: SingleBubbleView] = [:]
    private var currentNodes: [FileNode] = []
    private var lastLayoutSize: CGSize = .zero
    private var isUpdating = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBubbles(nodes: [FileNode], parentSize: Int64) {
        guard !isUpdating else { return }

        currentNodes = nodes

        // Update highlight state only
        for (id, view) in bubbleViews {
            view.isHighlighted = (id == highlightedNodeId)
        }

        // Rebuild if nodes changed or first time
        let nodeIds = Set(nodes.map { $0.id })
        let existingIds = Set(bubbleViews.keys)

        if nodeIds != existingIds {
            rebuildBubblesIfNeeded()
        }
    }

    private func rebuildBubblesIfNeeded() {
        guard !isUpdating else { return }
        guard bounds.width > 100, bounds.height > 100 else { return }
        guard !currentNodes.isEmpty else { return }

        isUpdating = true
        defer { isUpdating = false }

        // Remove old views
        for view in bubbleViews.values {
            view.removeFromSuperview()
        }
        bubbleViews.removeAll()

        let positions = computePositions(nodes: currentNodes, parentSize: 1, in: bounds.size)

        for (node, pos) in positions {
            let bubbleView = SingleBubbleView(
                frame: NSRect(
                    x: pos.x - pos.radius,
                    y: pos.y - pos.radius,
                    width: pos.radius * 2,
                    height: pos.radius * 2
                )
            )
            bubbleView.node = node
            bubbleView.radius = pos.radius
            bubbleView.isHighlighted = (node.id == highlightedNodeId)
            bubbleView.onSelect = { [weak self] in self?.onSelect?(node) }
            bubbleView.onHover = { [weak self] hovering in
                self?.onHover?(hovering ? node : nil)
            }
            bubbleView.translatesAutoresizingMaskIntoConstraints = true

            addSubview(bubbleView)
            bubbleViews[node.id] = bubbleView
        }

        lastLayoutSize = bounds.size
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Only rebuild if size changed significantly and not currently updating
        if !isUpdating && !currentNodes.isEmpty {
            let sizeDiff = abs(newSize.width - lastLayoutSize.width) + abs(newSize.height - lastLayoutSize.height)
            if sizeDiff > 50 {
                rebuildBubblesIfNeeded()
            }
        }
    }

    private func computePositions(nodes: [FileNode], parentSize: Int64, in size: CGSize) -> [(FileNode, BubblePosition)] {
        let sortedNodes = nodes.sorted { $0.size > $1.size }
        let topNodes = Array(sortedNodes.prefix(20))

        let centerX = size.width / 2
        let centerY = size.height / 2
        let containerRadius = min(size.width, size.height) / 2 - 40

        var result: [(FileNode, BubblePosition)] = []
        var placedBubbles: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []

        let totalSize = topNodes.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > 0 else { return [] }

        let minRadius: CGFloat = 24
        let maxBubbleRadius = containerRadius * 0.42

        for (index, node) in topNodes.enumerated() {
            let sizeRatio = sqrt(Double(node.size) / Double(totalSize))
            let radius = max(minRadius, min(maxBubbleRadius, CGFloat(sizeRatio) * containerRadius * 1.4))

            var placed = false
            var finalX = centerX
            var finalY = centerY

            if index == 0 {
                placed = true
            } else {
                let padding: CGFloat = 10

                outer: for dist in stride(from: CGFloat(0), to: containerRadius, by: 8) {
                    let angleCount = max(16, Int(dist / 6))
                    for a in 0..<angleCount {
                        let angle = CGFloat(a) * (2 * .pi / CGFloat(angleCount))
                        let testX = centerX + cos(angle) * dist
                        let testY = centerY + sin(angle) * dist

                        let distFromCenter = hypot(testX - centerX, testY - centerY)
                        if distFromCenter + radius > containerRadius {
                            continue
                        }

                        var overlaps = false
                        for other in placedBubbles {
                            let d = hypot(testX - other.x, testY - other.y)
                            if d < radius + other.r + padding {
                                overlaps = true
                                break
                            }
                        }

                        if !overlaps {
                            finalX = testX
                            finalY = testY
                            placed = true
                            break outer
                        }
                    }
                }
            }

            if placed {
                result.append((node, BubblePosition(x: finalX, y: finalY, radius: radius)))
                placedBubbles.append((x: finalX, y: finalY, r: radius))
            }
        }

        return result
    }
}

struct BubblePosition {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
}
