#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    let isCompact: Bool

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView()
        view.updateCompactMode(isCompact)
        return view
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {
        nsView.updateCompactMode(isCompact)
    }
}

final class WindowChromeView: NSView {
    private var desiredCompactMode = false
    private var appliedCompactMode: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowConfiguration()

        DispatchQueue.main.async { [weak self] in
            self?.applyWindowConfiguration()
        }
    }

    func updateCompactMode(_ isCompact: Bool) {
        desiredCompactMode = isCompact
        applyWindowConfiguration()
    }

    private func applyWindowConfiguration() {
        guard let window else { return }
        configureTransparentWindow(window)
        hideNativeWindowButtons(in: window)

        guard let appliedCompactMode else {
            self.appliedCompactMode = desiredCompactMode
            return
        }
        guard appliedCompactMode != desiredCompactMode else { return }

        self.appliedCompactMode = desiredCompactMode

        let sidebarWidthDifference: CGFloat = 116
        let widthChange = desiredCompactMode
            ? -sidebarWidthDifference
            : sidebarWidthDifference
        let minimumWidth: CGFloat = desiredCompactMode ? 284 : 400

        var targetFrame = window.frame
        targetFrame.size.width = max(
            minimumWidth,
            targetFrame.width + widthChange
        )

        if let visibleFrame = window.screen?.visibleFrame {
            targetFrame.size.width = min(targetFrame.width, visibleFrame.width)
            targetFrame.origin.x = min(
                max(targetFrame.origin.x, visibleFrame.minX),
                visibleFrame.maxX - targetFrame.width
            )
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.42,
                0,
                0.20,
                1
            )
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func configureTransparentWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func hideNativeWindowButtons(in window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
#endif
