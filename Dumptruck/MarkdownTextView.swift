//
//  MarkdownTextView.swift
//  Dumptruck
//
//  NSViewRepresentable wrapper around NSTextView. SwiftUI's TextEditor on
//  macOS 14 doesn't expose enough to do per-range styling for Markdown
//  highlighting, so we drop down to AppKit for the editor surface.
//
//  M2 (this milestone): plain unstyled editing with Return-to-save and
//  Shift+Return-to-newline routing.
//  M5: A MarkdownHighlighter (NSTextStorageDelegate) is attached here to
//  paint syntax inline.
//

import AppKit
import SwiftUI

/// SwiftUI wrapper around NSTextView. Two-way bound text, exposes save/cancel
/// callbacks the SwiftUI parent can implement.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    /// Font used for the editor. Defaults to SF Mono 14 — Markdown-y, mono-spaced,
    /// keeps tables/code blocks readable. User override comes via Settings (M7).
    var font: NSFont = MarkdownTextView.defaultFont()

    /// Whether system Reduce Motion is on. Disables any selection-flash effects
    /// inside the editor when true.
    var reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Called when the user presses Return (no shift). Parent saves the file.
    var onSave: () -> Void

    /// Called when the user presses Esc. Parent dismisses the panel.
    var onCancel: () -> Void

    /// Called whenever the text changes — drives draft autosave debounce.
    var onTextChange: (String) -> Void

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // NSTextView.scrollableTextView() gives us a properly configured scroll
        // view + text view pair. Saves a lot of fiddly setup.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = font
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor

        // Accessibility: announce the role and a meaningful label. VoiceOver
        // users hear "Markdown editor, text area".
        textView.setAccessibilityLabel("Markdown editor")
        textView.setAccessibilityRole(.textArea)

        // Custom key routing: Return = save, Shift+Return = newline, Esc = cancel.
        // We do this by inserting a key-event monitor on the text view's window.
        // Coordinator stores the monitor reference so we can remove it on dismantle.
        context.coordinator.installKeyMonitor(on: textView)

        // Attach the Markdown highlighter (M5 fills in the body; for M2 it's a
        // pass-through so the editor still works.)
        if let storage = textView.textStorage {
            let highlighter = MarkdownHighlighter(font: font)
            storage.delegate = highlighter
            context.coordinator.highlighter = highlighter
            // Initial pass so any pre-existing draft text is styled correctly.
            highlighter.highlight(storage)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Avoid a feedback loop: if SwiftUI text matches what's already in the
        // view, do nothing. Otherwise replace contents while preserving cursor
        // position where possible.
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            // Clamp the selection if the new text is shorter.
            let safeLocation = min(selected.location, text.utf16.count)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            // Re-run the highlighter so the new content gets styled.
            if let storage = textView.textStorage {
                context.coordinator.highlighter?.highlight(storage)
            }
        }

        if textView.font != font {
            textView.font = font
            context.coordinator.highlighter?.baseFont = font
            if let storage = textView.textStorage {
                context.coordinator.highlighter?.highlight(storage)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
    }

    /// Default font factory: SF Mono if available, fall back to the system
    /// monospaced font, and finally to NSFont.systemFont(ofSize:).
    static func defaultFont(size: CGFloat = 14) -> NSFont {
        if let sfmono = NSFont(name: "SF Mono", size: size) {
            return sfmono
        }
        if let menlo = NSFont(name: "Menlo", size: size) {
            return menlo
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownTextView
        var keyMonitor: Any?
        var highlighter: MarkdownHighlighter?

        init(parent: MarkdownTextView) {
            self.parent = parent
        }

        // NSTextViewDelegate: pipe edits back to SwiftUI binding.
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            // The Binding is `let` inside Coordinator's stored `parent`, but
            // Binding<T> assignment via the closure semantics works because
            // wrappedValue is mutable through the projected setter.
            parent.text = newValue
            parent.onTextChange(newValue)
        }

        // MARK: Key monitor

        /// Local-only monitor (scoped to this app, not global). Routes:
        ///   Return alone        → onSave
        ///   Shift+Return        → insert newline (let the view handle it)
        ///   Esc                 → onCancel
        func installKeyMonitor(on textView: NSTextView) {
            removeKeyMonitor()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak textView] event in
                guard let self, let textView, textView.window?.firstResponder === textView else {
                    return event
                }

                // Return = 36, Numeric Enter = 76. Treat both the same.
                let isReturn = event.keyCode == 36 || event.keyCode == 76
                let isEscape = event.keyCode == 53

                if isEscape {
                    self.parent.onCancel()
                    return nil
                }
                if isReturn {
                    if event.modifierFlags.contains(.shift) {
                        // Shift+Return = newline. Let the text view handle it.
                        return event
                    }
                    // Plain Return = save. Swallow the event so no newline is inserted.
                    self.parent.onSave()
                    return nil
                }
                return event
            }
        }

        func removeKeyMonitor() {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }

        deinit {
            removeKeyMonitor()
        }
    }
}
