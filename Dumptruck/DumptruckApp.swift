//
//  DumptruckApp.swift
//  Dumptruck
//
//  Menubar-only quick-capture app. Entry point.
//

import SwiftUI
import AppKit
import KeyboardShortcuts

@main
struct DumptruckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings scene: standard macOS ⌘, behavior, lives in the system menu
        // when the Settings window is focused. Real settings UI in SettingsView.
        Settings {
            SettingsView()
        }
    }
}

/// AppDelegate owns:
///   * the menubar status item (via StatusItemController)
///   * the global hotkey registration (via KeyboardShortcuts)
///   * lifecycle plumbing (activation policy, observers)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only: never show in Dock or ⌘Tab.
        NSApp.setActivationPolicy(.accessory)

        // Build the menubar item. Honor the hide-icon setting if set.
        let controller = StatusItemController()
        statusItemController = controller
        if SettingsStore.shared.hideMenubarIcon {
            controller.setVisible(false)
        }

        // Wire the global shortcut. Default is ⌘\, configurable in Settings.
        KeyboardShortcuts.onKeyDown(for: .toggleCapture) {
            Task { @MainActor in
                CaptureWindowController.shared.toggle()
            }
        }

        // Apply theme override (system/light/dark) at launch.
        applyThemeOverride()

        // Observe runtime setting changes that need a side effect.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyHideMenubarIcon),
            name: .dumptruckHideMenubarIconChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyThemeOverride),
            name: .dumptruckThemeOverrideChanged,
            object: nil
        )

        // Make sure the suggested save folder exists by the time the user
        // first attempts to save. We don't *force* the choice on them; the
        // first save will prompt with NSOpenPanel.
        let suggested = SettingsDefaults.suggestedSaveFolderURL
        if !FileManager.default.fileExists(atPath: suggested.path) {
            try? FileManager.default.createDirectory(
                at: suggested,
                withIntermediateDirectories: true
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menubar app — closing the capture window must NOT quit.
        false
    }

    // MARK: - Setting observers

    @objc private func applyHideMenubarIcon() {
        statusItemController?.setVisible(!SettingsStore.shared.hideMenubarIcon)
    }

    @objc private func applyThemeOverride() {
        switch SettingsStore.shared.themeOverride {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil // match system
        }
    }
}
