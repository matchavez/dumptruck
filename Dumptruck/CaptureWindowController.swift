//
//  CaptureWindowController.swift
//  Dumptruck
//
//  Coordinates the lifecycle of the capture NSPanel:
//   * lazily builds the panel + SwiftUI host
//   * restores last-known window frame from UserDefaults
//   * shows / hides / toggles on left-click + global shortcut
//   * persists frame on close
//   * routes save attempts to FileWriter
//   * forwards text changes to DraftStore
//

import AppKit
import SwiftUI

@MainActor
final class CaptureWindowController: NSObject {
    /// Singleton — every entry point (status item click, global shortcut) calls
    /// the same instance so toggling state is coherent.
    static let shared = CaptureWindowController()

    private var panel: CapturePanel?
    private var hostingController: NSHostingController<CaptureView>?

    private let fileWriter = FileWriter()
    private let draftStore = DraftStore()
    private let soundPlayer = SoundPlayer()
    private var draftDebounce: DispatchWorkItem?

    /// Default size when there's no saved frame yet. Roughly the proportions of
    /// the Spotlight panel.
    private let defaultSize = NSSize(width: 560, height: 280)

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    // MARK: - Public API

    /// Toggles the panel: if visible, hide; if hidden, build/show + restore draft.
    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    /// Force-show the panel (used by both the menubar left-click and the shortcut).
    func show() {
        let panel = ensurePanel()

        // Always seed the editor with the latest draft. This handles the case
        // where the panel was kept alive but the on-disk draft changed (e.g.
        // future iOS sync). Cheap to read; safe to do every time.
        let draft = draftStore.load() ?? ""
        rebuildHostingController(with: draft)

        // Restore frame *each show* so multi-monitor moves are sticky.
        if let frame = restoredFrame() {
            panel.setFrame(frame, display: false)
        } else {
            centerPanel(panel)
        }

        panel.makeKeyAndOrderFront(nil)

        // Force key window — without this, the editor inside doesn't get keystrokes
        // when the panel comes up over a full-screen app.
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Force-hide the panel (callable from the menubar menu, the shortcut, or
    /// the SwiftUI view's onCancel callback).
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Build / wire up

    private func ensurePanel() -> CapturePanel {
        if let panel { return panel }
        let initialRect = NSRect(origin: .zero, size: defaultSize)
        let newPanel = CapturePanel(contentRect: initialRect)
        newPanel.delegate = self
        self.panel = newPanel
        return newPanel
    }

    private func rebuildHostingController(with text: String) {
        guard let panel else { return }

        let view = CaptureView(
            initialText: text,
            onSave: { [weak self] body in self?.attemptSave(body: body) },
            onCancel: { [weak self] in self?.hide() },
            onTextChange: { [weak self] newText in self?.scheduleDraftSave(newText) }
        )

        let hc = NSHostingController(rootView: view)
        hostingController = hc
        panel.contentView = hc.view

        // Make the editor first responder so typing starts immediately.
        DispatchQueue.main.async {
            if let textView = self.findFirstTextView(in: hc.view) {
                panel.makeFirstResponder(textView)
            }
        }
    }

    /// Walks the view hierarchy looking for the embedded NSTextView. We need
    /// this to make it first responder after the hosting controller installs
    /// its subview tree.
    private func findFirstTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findFirstTextView(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Save flow

    /// Attempts to write `body` via FileWriter. Returns a Result the view uses
    /// to flash success or error.
    private func attemptSave(body: String) -> Result<URL, Error>? {
        // No save folder? Prompt the user (M3) and abort this save.
        guard let folder = SettingsStore.shared.resolveSaveFolder() else {
            promptForSaveFolder()
            return nil
        }

        do {
            let url = try fileWriter.write(body: body, into: folder)
            draftStore.clear()
            if SettingsStore.shared.soundEnabled {
                soundPlayer.playSaveSound()
            }
            return .success(url)
        } catch {
            NSLog("[Dumptruck] Save failed: \(error)")
            return .failure(error)
        }
    }

    /// Opens an NSOpenPanel for the user to pick a save folder. Called the first
    /// time they attempt to save without one configured. Saves the choice via
    /// SettingsStore.
    private func promptForSaveFolder() {
        let open = NSOpenPanel()
        open.title = "Choose Dumptruck save folder"
        open.message = "Pick where your captured notes will be saved."
        open.prompt = "Choose"
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.allowsMultipleSelection = false
        open.canCreateDirectories = true
        open.directoryURL = SettingsDefaults.suggestedSaveFolderURL

        // Sheet-attach to the panel if we have one, otherwise modal.
        if let panel = self.panel, panel.isVisible {
            open.beginSheetModal(for: panel) { [weak self] response in
                guard response == .OK, let url = open.url else { return }
                SettingsStore.shared.setSaveFolder(url)
                NotificationCenter.default.post(name: .dumptruckSaveFolderChanged, object: nil)
                // Don't auto-retry the save — the user typed something, they
                // can hit Return again. Less surprising.
                self?.flashFolderChosenMessage(url)
            }
        } else {
            let response = open.runModal()
            guard response == .OK, let url = open.url else { return }
            SettingsStore.shared.setSaveFolder(url)
            NotificationCenter.default.post(name: .dumptruckSaveFolderChanged, object: nil)
        }
    }

    private func flashFolderChosenMessage(_ url: URL) {
        // Trivial NSAlert-free feedback: log + tooltip update. The SwiftUI flash
        // overlay is owned by CaptureView, so we don't drive it directly from
        // here.
        NSLog("[Dumptruck] Save folder set to \(url.path)")
    }

    // MARK: - Draft persistence

    /// Writes the draft to disk on a 500ms debounce so typing doesn't hammer
    /// the disk. Called on every keystroke from the SwiftUI binding.
    private func scheduleDraftSave(_ text: String) {
        draftDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if text.isEmpty {
                self?.draftStore.clear()
            } else {
                self?.draftStore.save(text)
            }
        }
        draftDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Frame memory

    private func restoredFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.lastWindowFrame) else {
            return nil
        }
        let rect = NSRectFromString(raw)
        guard rect.size.width > 100, rect.size.height > 80 else { return nil }
        // Clamp to a screen that still exists (in case the monitor was unplugged).
        if NSScreen.screens.contains(where: { NSIntersectsRect($0.visibleFrame, rect) }) {
            return rect
        }
        return nil
    }

    private func persistFrame() {
        guard let frame = panel?.frame else { return }
        let raw = NSStringFromRect(frame)
        UserDefaults.standard.set(raw, forKey: SettingsKey.lastWindowFrame)
    }

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 80 // bias upward so it sits above center
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Notifications

    @objc private func panelWillClose(_ note: Notification) {
        guard let closing = note.object as? NSWindow, closing === panel else { return }
        persistFrame()
    }
}

// MARK: - NSWindowDelegate

extension CaptureWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // When the user clicks away, dismiss like Spotlight. The frame is saved
        // via panelWillClose. We intentionally don't dismiss when window
        // resigns *main* — non-activating panels never become main.
        // Caveat: don't dismiss if a sheet is up (e.g. the folder picker).
        if let panel = panel, panel.attachedSheet != nil { return }
        hide()
    }

    func windowWillClose(_ notification: Notification) {
        persistFrame()
    }
}
