//
//  StatusItemController.swift
//  Dumptruck
//
//  Owns the menubar NSStatusItem. Routes left-click → capture window (M2),
//  right-click → admin menu (Settings, About, Quit).
//

import AppKit

/// SF Symbol used for the menubar icon. `truck.box` is on-brand for "Dumptruck"
/// and is available from macOS 13+. Treated as a template image so it tints
/// correctly in both light and dark menubars.
private enum MenubarIcon {
    static let symbolName = "truck.box"
    static let accessibilityLabel = "Dumptruck"
    static let tooltip = "Dumptruck — Quick Capture"
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let rightClickMenu: NSMenu

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rightClickMenu = StatusItemController.makeRightClickMenu()
        super.init()

        configureButton()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }

        let image = NSImage(
            systemSymbolName: MenubarIcon.symbolName,
            accessibilityDescription: MenubarIcon.accessibilityLabel
        )
        image?.isTemplate = true // tints correctly in light/dark menubars
        button.image = image
        button.toolTip = MenubarIcon.tooltip

        // We handle both mouse-down events ourselves so we can route left vs right.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.target = self
        button.action = #selector(handleClick(_:))

        // Accessibility: VoiceOver announces "Dumptruck, button" and the tooltip.
        button.setAccessibilityLabel(MenubarIcon.accessibilityLabel)
        button.setAccessibilityHelp("Open the Dumptruck quick-capture window. Right-click for options.")
    }

    private static func makeRightClickMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About Dumptruck",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Dumptruck",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        // Wire menu actions to this controller. Setting target on each item so
        // they don't fall through to the responder chain.
        return menu
    }

    // MARK: - Click routing

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            // Fallback: treat as left-click.
            openCaptureWindow()
            return
        }

        switch event.type {
        case .rightMouseDown:
            showRightClickMenu()
        case .leftMouseDown:
            // ⌃-left-click is the macOS convention for "show context menu".
            if event.modifierFlags.contains(.control) {
                showRightClickMenu()
            } else {
                openCaptureWindow()
            }
        default:
            openCaptureWindow()
        }
    }

    private func showRightClickMenu() {
        // Make sure every item targets this controller so the responder-chain
        // selectors below get hit.
        for item in rightClickMenu.items {
            item.target = self
        }
        statusItem.menu = rightClickMenu
        statusItem.button?.performClick(nil)
        // Detach the menu immediately afterward so the next left-click hits our
        // action again instead of just opening the menu.
        statusItem.menu = nil
    }

    private func openCaptureWindow() {
        // Toggle, not just show: a second left-click on the menubar icon while
        // the capture window is up should dismiss it. Spotlight-style.
        Task { @MainActor in
            CaptureWindowController.shared.toggle()
        }
    }

    // MARK: - Visibility (M7)

    /// Show or hide the menubar icon entirely. When hidden, the app is
    /// reachable only via the global shortcut. Settings remain accessible via
    /// the standard ⌘, route inside the Settings window once open.
    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    // MARK: - Menu actions

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
