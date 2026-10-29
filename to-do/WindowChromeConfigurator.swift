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
    private weak var configuredWindow: NSWindow?

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
        removeUnusedMainMenus()

        guard let appliedCompactMode else {
            self.appliedCompactMode = desiredCompactMode
            window.contentMinSize = NSSize(
                width: desiredCompactMode ? 284 : 400,
                height: 380
            )
            return
        }
        guard appliedCompactMode != desiredCompactMode else { return }

        self.appliedCompactMode = desiredCompactMode

        let compactMinimumSize = NSSize(width: 284, height: 380)
        let expandedMinimumSize = NSSize(width: 400, height: 380)

        // Relax the width constraint before resizing so AppKit does not snap
        // the window to the expanded minimum ahead of the animation.
        window.contentMinSize = compactMinimumSize

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
                0.58,
                1
            )
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            window.contentMinSize = self.desiredCompactMode
                ? compactMinimumSize
                : expandedMinimumSize
        }
    }

    private func configureTransparentWindow(_ window: NSWindow) {
        guard configuredWindow !== window else { return }
        configuredWindow = window

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        window.identifier = NSUserInterfaceItemIdentifier("MainTodoWindow")
        window.setFrameAutosaveName("MainTodoWindowFrame")
        window.isRestorable = true
    }

    private func removeUnusedMainMenus() {
        guard let mainMenu = NSApp.mainMenu else {
            return
        }

        let unusedTitles = Set(["View", "Format", "Help"])
        for item in mainMenu.items where unusedTitles.contains(item.title) {
            mainMenu.removeItem(item)
        }
    }

    private func hideNativeWindowButtons(in window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
#endif
