//
//  CapturePanel.swift
//  Dumptruck
//
//  NSPanel subclass for the floating capture window. Two behaviors we can't
//  get from SwiftUI's Window/MenuBarExtra:
//    1. Non-activating: appears without stealing focus from the frontmost app.
//    2. canBecomeKey: still accepts keystrokes from the user.
//
//  These two together give us the Spotlight / Alfred style "panel" feel.
//

import AppKit

/// Floating capture window.
final class CapturePanel: NSPanel {
    /// Designated initializer. Frame is provisional — CaptureWindowController
    /// either restores the last-known frame from SettingsStore or computes a
    /// sensible center-screen default.
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView,
                .nonactivatingPanel,
                .hudWindow,
                .utilityWindow,
            ],
            backing: .buffered,
            defer: false
        )

        // Native HUD-style appearance: dark, vibrant, blends with desktop.
        // Reduce Transparency is honored automatically by .hudWindow.
        isFloatingPanel = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        level = .floating
        animationBehavior = .utilityWindow

        // Title bar is present (for ⌘W / drag affordances) but transparent so
        // the .hudWindow chrome reads as a single rounded panel.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        title = "Dumptruck"

        // Visible across all Spaces, including over full-screen apps. Without
        // this, ⌘\ from inside a full-screen app would be a no-op.
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        // Standard close button hides the window instead of releasing it.
        isReleasedWhenClosed = false

        // Honor Reduce Transparency in the system Accessibility prefs.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            backgroundColor = NSColor.windowBackgroundColor
        }
    }

    // MARK: - Key handling

    /// Non-activating panels normally refuse to become key. We override so the
    /// editor inside actually receives keystrokes. Without this, typing does
    /// nothing.
    override var canBecomeKey: Bool { true }

    /// We don't want the panel to take "main" status — that's reserved for the
    /// frontmost app's primary window. Keeps menus and ⌘Tab behavior natural.
    override var canBecomeMain: Bool { false }

    /// Esc → close. NSResponder's cancelOperation is the right hook for this;
    /// it's what `keyDown` falls through to when the user presses Esc and
    /// nothing else handles it.
    override func cancelOperation(_ sender: Any?) {
        // The controller listens for `NSWindow.willCloseNotification` so closing
        // here cleanly tears everything down (saves draft, persists frame).
        close()
    }
}
