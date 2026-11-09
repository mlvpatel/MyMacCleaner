import Testing
import AppKit
import Combine
@testable import MyMacCleaner

// MARK: - Space Lens Bubble Tests

@Suite("Space Lens Bubble Tests")
@MainActor
struct SpaceLensBubbleTests {
    /// More children than the 20 bubbles the view places, as in a typical home folder.
    private static let childCount = 30

    private func makeContainer() -> BubbleContainerView {
        BubbleContainerView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    private func makeNodes() -> [FileNode] {
        (0..<Self.childCount).map { index in
            FileNode(
                name: "item\(index)",
                url: URL(fileURLWithPath: "/tmp/item\(index)"),
                size: Int64((Self.childCount - index) * 1_000),
                isDirectory: false,
                children: []
            )
        }
    }

    @Test("A hover update with the same children keeps every bubble view and moves the highlight")
    func unchangedChildrenKeepBubbleViews() {
        let container = makeContainer()
        let nodes = makeNodes()
        container.updateBubbles(nodes: nodes, parentSize: 0)
        let initialBubbles = container.subviews

        container.highlightedNodeId = nodes[0].id
        container.updateBubbles(nodes: nodes, parentSize: 0)

        // Bound to a constant: inside #expect, `elementsEqual(_:by: ===)` is discarded and always passes.
        let keptSameViews = container.subviews.elementsEqual(initialBubbles) { $0 === $1 }
        let highlighted = container.subviews
            .compactMap { $0 as? SingleBubbleView }
            .filter(\.isHighlighted)
        #expect(!initialBubbles.isEmpty)
        #expect(keptSameViews)
        #expect(highlighted.map(\.node?.id) == [nodes[0].id])
    }

    @Test("New children replace the bubble views")
    func changedChildrenRebuildBubbleViews() {
        let container = makeContainer()
        container.updateBubbles(nodes: makeNodes(), parentSize: 0)
        let initialBubbles = container.subviews

        container.updateBubbles(nodes: makeNodes(), parentSize: 0)

        let reusedAnyView = container.subviews.contains { view in initialBubbles.contains { $0 === view } }
        #expect(!container.subviews.isEmpty)
        #expect(!reusedAnyView)
    }
}

// MARK: - Space Lens State Tests

@Suite("Space Lens State Tests")
@MainActor
struct SpaceLensStateTests {
    private func makeTree() -> FileNode {
        let file = FileNode(name: "a.bin", url: URL(fileURLWithPath: "/tmp/root/a.bin"), size: 10, isDirectory: false, children: [])
        return FileNode(name: "root", url: URL(fileURLWithPath: "/tmp/root"), size: 10, isDirectory: true, children: [file])
    }

    private func makeViewModel(releaseDelay: Duration) -> SpaceLensViewModel {
        let viewModel = SpaceLensViewModel(treeReleaseDelay: releaseDelay)
        let root = makeTree()
        viewModel.rootNode = root
        viewModel.currentNode = root
        viewModel.navigationStack = [root]
        return viewModel
    }

    @Test("Hovering changes only the hover object, not the view model every Space Lens view observes")
    func hoverDoesNotInvalidateViewModel() {
        let viewModel = makeViewModel(releaseDelay: .seconds(60))
        let node = makeTree().children[0]
        var changes = 0
        let subscription = viewModel.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        viewModel.hoverNode(node)

        #expect(viewModel.hover.node === node)
        #expect(changes == 0)
    }

    @Test("Leaving the page releases the tree after the idle delay")
    func leavingReleasesTree() async {
        let viewModel = makeViewModel(releaseDelay: .zero)

        viewModel.viewDidAppear()
        viewModel.viewDidDisappear()
        await viewModel.releaseTask?.value

        #expect(viewModel.rootNode == nil)
        #expect(viewModel.currentNode == nil)
        #expect(viewModel.navigationStack.isEmpty)
    }

    @Test("Coming back before the delay, or still showing the tree elsewhere, keeps it")
    func visibleTreeIsKept() {
        let viewModel = makeViewModel(releaseDelay: .seconds(60))

        // The Space Lens section and the Disk Cleaner tab can overlap during a switch.
        viewModel.viewDidAppear()
        viewModel.viewDidAppear()
        viewModel.viewDidDisappear()
        #expect(viewModel.releaseTask == nil)

        viewModel.viewDidDisappear()
        #expect(viewModel.releaseTask != nil)
        viewModel.viewDidAppear()

        #expect(viewModel.releaseTask == nil)
        #expect(viewModel.rootNode != nil)
    }
}
