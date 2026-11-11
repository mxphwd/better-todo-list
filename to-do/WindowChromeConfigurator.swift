#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    let isCompact: Bool
    let isDesktopMode: Bool
    let isLocationFixed: Bool
    let glassOpacity: Double

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView()
        view.updateConfiguration(
            isCompact: isCompact,
            isDesktopMode: isDesktopMode,
            isLocationFixed: isLocationFixed,
            glassOpacity: glassOpacity
        )
        return view
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {
        nsView.updateConfiguration(
            isCompact: isCompact,
            isDesktopMode: isDesktopMode,
            isLocationFixed: isLocationFixed,
            glassOpacity: glassOpacity
        )
    }
}

final class WindowChromeView: NSView {
    private var desiredCompactMode = false
    private var desiredDesktopMode = false
    private var desiredLocationFixed = false
    private var desiredGlassOpacity = 0.82
    private var appliedCompactMode: Bool?
    private var appliedDesktopMode: Bool?
    private weak var configuredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowConfiguration()

        DispatchQueue.main.async { [weak self] in
            self?.applyWindowConfiguration()
        }
    }

    func updateConfiguration(
        isCompact: Bool,
        isDesktopMode: Bool,
        isLocationFixed: Bool,
        glassOpacity: Double
    ) {
        desiredCompactMode = isCompact
        desiredDesktopMode = isDesktopMode
        desiredLocationFixed = isLocationFixed
        desiredGlassOpacity = glassOpacity
        applyWindowConfiguration()
    }

    private func applyWindowConfiguration() {
        guard let window else { return }
        configureTransparentWindow(window)
        hideNativeWindowButtons(in: window)
        removeUnusedMainMenus()
        applyDesktopMode(to: window)
        applyLocationLock(to: window)
        updateWindowShadow(for: window)

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
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                0.78,
                0.28,
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

    private func applyDesktopMode(to window: NSWindow) {
        guard appliedDesktopMode != desiredDesktopMode else { return }
        appliedDesktopMode = desiredDesktopMode

        if desiredDesktopMode {
            // Stay above Finder's desktop surface so the window remains interactive,
            // while remaining far below every normal application window.
            let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .stationary, .ignoresCycle])
        } else {
            window.level = .normal
            window.collectionBehavior.subtract([.canJoinAllSpaces, .stationary, .ignoresCycle])
        }
    }

    private func applyLocationLock(to window: NSWindow) {
        window.isMovable = !desiredLocationFixed
        window.isMovableByWindowBackground = !desiredLocationFixed
    }

    private func updateWindowShadow(for window: NSWindow) {
        window.hasShadow = !desiredDesktopMode && desiredGlassOpacity > 0.001
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
