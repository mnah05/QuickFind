import AppKit
import SwiftUI

@MainActor
final class LauncherPanel: NSPanel {
    static let panelSize = NSSize(width: 750, height: 480)
    private let cornerRadius: CGFloat = 16

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        animationBehavior = .utilityWindow
        title = "QuickFind"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.closeButton)?.superview?.isHidden = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        effect.autoresizingMask = [.width, .height]
        effect.setAccessibilityElement(false)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        contentView = effect
        setAccessibilityRole(.window)
        setAccessibilityLabel("QuickFind")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        let originX = min(max(visible.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        let originY = min(max(visible.midY - size.height / 2 + 48, visible.minY), max(visible.minY, visible.maxY - size.height))
        setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
