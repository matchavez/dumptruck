//
//  ShortcutNames.swift
//  Dumptruck
//
//  Names + defaults for our global hotkeys. We use Sindre Sorhus's
//  `KeyboardShortcuts` (https://github.com/sindresorhus/KeyboardShortcuts) via
//  Swift Package Manager.
//
//  Why KeyboardShortcuts (and not a hand-rolled Carbon RegisterEventHotKey
//  wrapper):
//    * It already wraps Carbon properly (Carbon hot-keys are still the only
//      reliable way to register a system-wide modifier+key combo).
//    * It ships a SwiftUI Recorder view we can drop into Settings.
//    * It persists user-recorded shortcuts to UserDefaults under our domain.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggle the capture panel. Default: ⌘\
    ///
    /// `.backslash` is the US-layout backslash; on other layouts the same
    /// physical key produces a different char, which is what we want — users
    /// recording a new shortcut see what their keyboard actually produces.
    static let toggleCapture = Self(
        "toggleCapture",
        default: .init(.backslash, modifiers: [.command])
    )
}
