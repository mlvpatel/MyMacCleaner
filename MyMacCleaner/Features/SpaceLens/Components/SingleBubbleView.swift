import AppKit
import SwiftUI

// MARK: - Single Bubble NSView

class SingleBubbleView: NSView {
    var node: FileNode?
    var radius: CGFloat = 0
    var isHighlighted: Bool = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    private var isHovered: Bool = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    private var isActive: Bool { isHovered || isHighlighted }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        // Highlight on press
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onSelect?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let node = node else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let r = radius

        // Outer glow
        ctx.saveGState()
        let glowColor = node.color.cgColor?.copy(alpha: isActive ? 0.5 : 0.15) ?? CGColor(gray: 0.5, alpha: 0.15)
        ctx.setShadow(offset: .zero, blur: isActive ? 20 : 10, color: glowColor)
        ctx.setFillColor(glowColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()

        // Main bubble gradient
        let colors: [CGColor] = [
            node.color.cgColor?.copy(alpha: isActive ? 0.95 : 0.6) ?? CGColor(gray: 0.5, alpha: 0.6),
            node.color.cgColor?.copy(alpha: isActive ? 0.7 : 0.35) ?? CGColor(gray: 0.5, alpha: 0.35)
        ]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else {
            // Fallback: draw simple filled ellipse if gradient creation fails
            ctx.setFillColor(colors.first ?? CGColor(gray: 0.5, alpha: 0.6))
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            return
        }

        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.clip()
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.3), startRadius: 0, endCenter: center, endRadius: r, options: [])
        ctx.restoreGState()

        // Shine
        ctx.saveGState()
        let shineColors: [CGColor] = [
            CGColor(gray: 1, alpha: isActive ? 0.5 : 0.25),
            CGColor(gray: 1, alpha: 0)
        ]
        guard let shineGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shineColors as CFArray, locations: [0, 1]) else {
            ctx.restoreGState()
            return
        }
        ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.clip()
        ctx.drawLinearGradient(shineGradient, start: CGPoint(x: center.x - r, y: center.y - r), end: center, options: [])
        ctx.restoreGState()

        // Border
        ctx.saveGState()
        ctx.setLineWidth(isActive ? 3 : 2)
        let borderColor = CGColor(gray: 1, alpha: isActive ? 0.9 : 0.5)
        ctx.setStrokeColor(borderColor)
        ctx.strokeEllipse(in: CGRect(x: center.x - r + 1, y: center.y - r + 1, width: r * 2 - 2, height: r * 2 - 2))
        ctx.restoreGState()

        // Draw text content
        drawContent(in: ctx, center: center, radius: r)
    }

    private func drawContent(in ctx: CGContext, center: CGPoint, radius: CGFloat) {
        guard let node = node else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        // Icon background
        if radius > 32 {
            let iconSize = min(radius * 0.45, 40)
            let iconRect = CGRect(
                x: center.x - iconSize / 2,
                y: center.y - iconSize / 2 - radius * 0.15,
                width: iconSize,
                height: iconSize
            )

            ctx.saveGState()
            ctx.setFillColor(CGColor(gray: 1, alpha: isActive ? 0.4 : 0.25))
            let path = NSBezierPath(roundedRect: iconRect, xRadius: 6, yRadius: 6)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Draw SF Symbol
            let config = NSImage.SymbolConfiguration(pointSize: min(radius * 0.2, 18), weight: .semibold)
            if let image = NSImage(systemSymbolName: node.icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let imageRect = CGRect(
                    x: center.x - image.size.width / 2,
                    y: center.y - image.size.height / 2 - radius * 0.15,
                    width: image.size.width,
                    height: image.size.height
                )
                image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }

        // Name
        if radius > 25 {
            let fontSize = min(radius * 0.12, 11)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let nameStr = node.name as NSString
            let nameSize = nameStr.size(withAttributes: attrs)
            let nameRect = CGRect(
                x: center.x - min(nameSize.width, radius * 1.4) / 2,
                y: center.y + (radius > 32 ? radius * 0.2 : 0) - nameSize.height / 2,
                width: min(nameSize.width, radius * 1.4),
                height: nameSize.height
            )
            nameStr.draw(in: nameRect, withAttributes: attrs)
        }

        // Size
        if radius > 38 {
            let fontSize = min(radius * 0.09, 9)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraphStyle
            ]
            let sizeStr = node.formattedSize as NSString
            let sizeSize = sizeStr.size(withAttributes: attrs)
            let sizeRect = CGRect(
                x: center.x - sizeSize.width / 2,
                y: center.y + radius * 0.35,
                width: sizeSize.width,
                height: sizeSize.height
            )
            sizeStr.draw(in: sizeRect, withAttributes: attrs)
        }
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }
}
