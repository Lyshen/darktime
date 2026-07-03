import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct SidebarResizeHandle: NSViewRepresentable {
    let currentWidth: Double
    let minWidth: Double
    let maxWidth: Double
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void

    func makeNSView(context: Context) -> SidebarResizeHandleView {
        SidebarResizeHandleView()
    }

    func updateNSView(_ nsView: SidebarResizeHandleView, context: Context) {
        nsView.currentWidth = currentWidth
        nsView.minWidth = minWidth
        nsView.maxWidth = maxWidth
        nsView.onChange = onChange
        nsView.onEnd = onEnd
        nsView.needsDisplay = true
    }
}

final class SidebarResizeHandleView: NSView {
    var currentWidth = 230.0
    var minWidth = 190.0
    var maxWidth = 340.0
    var onChange: ((Double) -> Void)?
    var onEnd: ((Double) -> Void)?

    private var dragStartWidth = 230.0
    private var dragStartX = 0.0
    private var isHovering = false
    private var trackingAreaRef: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartWidth = currentWidth
        dragStartX = Double(event.locationInWindow.x)
    }

    override func mouseDragged(with event: NSEvent) {
        let proposed = dragStartWidth + Double(event.locationInWindow.x) - dragStartX
        onChange?(clamped(proposed))
    }

    override func mouseUp(with event: NSEvent) {
        let proposed = dragStartWidth + Double(event.locationInWindow.x) - dragStartX
        onEnd?(clamped(proposed))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let alpha: CGFloat = isHovering ? 0.13 : 0.075
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, minWidth), maxWidth)
    }
}


