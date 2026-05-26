//
//  SettingsWindowController.swift
//  Dumptruck
//
//  Manages the Settings window directly as an NSWindow + NSHostingView.
//  The SwiftUI Settings{} scene approach relies on showSettingsWindow:, a
//  private selector that does not fire reliably for LSUIElement (menubar-only)
//  apps. This singleton bypasses that entirely.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.title = "Dumptruck Settings"
        win.contentView = NSHostingView(rootView: SettingsView())
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
