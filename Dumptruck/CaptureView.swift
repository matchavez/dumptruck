//
//  CaptureView.swift
//  Dumptruck
//
//  SwiftUI host view inside the capture NSPanel. Owns the editable text state,
//  the save-confirmation flash, and wires keyboard actions to the window
//  controller via the callbacks it was constructed with.
//

import SwiftUI
import AppKit

struct CaptureView: View {
    /// Editor text. Initial value is restored from the draft store by the
    /// CaptureWindowController before the view is shown.
    @State private var text: String = ""

    /// Saved-flash overlay state. Driven by `flash()` and respects Reduce Motion.
    @State private var showSavedFlash: Bool = false

    /// Last save status message used by the flash + announced to VoiceOver.
    @State private var statusMessage: String = ""

    @AppStorage(SettingsKey.editorFontName) private var editorFontName: String = SettingsDefaults.editorFontName
    @AppStorage(SettingsKey.editorFontSize) private var editorFontSize: Double = SettingsDefaults.editorFontSize

    /// Called when the user presses Return. Returns the file URL written so we
    /// can show a "Saved to X" announcement.
    let onSave: (String) -> Result<URL, Error>?

    /// Called when the user presses Esc. The controller closes the panel.
    let onCancel: () -> Void

    /// Called whenever text changes. The controller debounces and writes the draft.
    let onTextChange: (String) -> Void

    /// Initial text injected by the controller (typically a restored draft).
    let initialText: String

    init(
        initialText: String,
        onSave: @escaping (String) -> Result<URL, Error>?,
        onCancel: @escaping () -> Void,
        onTextChange: @escaping (String) -> Void
    ) {
        self.initialText = initialText
        self.onSave = onSave
        self.onCancel = onCancel
        self.onTextChange = onTextChange
        _text = State(initialValue: initialText)
    }

    var body: some View {
        ZStack {
            MarkdownTextView(
                text: $text,
                font: editorFont,
                onSave: { handleSave() },
                onCancel: { onCancel() },
                onTextChange: { newText in onTextChange(newText) }
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            // Saved-confirmation flash overlay. Single source of truth for the
            // checkmark + message. Hidden by default, fades in/out on save.
            if showSavedFlash {
                SavedFlashView(message: statusMessage)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity
                    ))
                    .allowsHitTesting(false)
                    .accessibilityLiveRegion(.assertive)
            }
        }
        .frame(minWidth: 480, minHeight: 220)
        .background(
            // .hudWindow gives us material; this just supplies a fallback color
            // when Reduce Transparency is on.
            Color.clear
        )
        .onAppear {
            // Make sure the initial text propagates back to the parent's draft
            // observer so an opened-with-draft session ticks the autosave.
            onTextChange(text)
        }
    }

    // MARK: - Save action

    /// Routes a save attempt through the parent and shows the appropriate flash.
    private func handleSave() {
        // Empty / whitespace-only buffer: nothing to save. Just dismiss.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onCancel()
            return
        }

        guard let result = onSave(text) else {
            // onSave intentionally returned nil — likely no save folder set
            // and the parent surfaced a sheet/prompt itself. Don't flash.
            return
        }

        switch result {
        case .success(let url):
            statusMessage = "Saved to \(url.lastPathComponent)"
            text = ""
            flash()
        case .failure(let error):
            statusMessage = "Save failed: \(error.localizedDescription)"
            flash(error: true)
        }
    }

    /// Show the saved flash for a short moment, then close the panel.
    private func flash(error: Bool = false) {
        if reduceMotion {
            // No animation: show briefly, then dismiss.
            showSavedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 1.6 : 0.45)) {
                showSavedFlash = false
                if !error { onCancel() }
            }
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                showSavedFlash = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 1.6 : 0.55)) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSavedFlash = false
                }
                // Close shortly after the flash fades, but never on error so
                // the user can read the message and act on it.
                if !error {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        onCancel()
                    }
                }
            }
        }
    }

    // MARK: - Font + a11y helpers

    private var editorFont: NSFont {
        if let custom = NSFont(name: editorFontName, size: editorFontSize) {
            return custom
        }
        return MarkdownTextView.defaultFont(size: editorFontSize)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// The "Saved to filename.md" overlay. Centered, semi-transparent, with a
/// checkmark glyph + text. Designed to be glanceable, not blocking.
private struct SavedFlashView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
