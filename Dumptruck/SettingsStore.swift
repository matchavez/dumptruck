//
//  SettingsStore.swift
//  Dumptruck
//
//  Centralized, @AppStorage-friendly settings. All user-facing preferences live here.
//  Most callers should use the @AppStorage keys directly so SwiftUI views update reactively.
//  This file owns the *names* of those keys and the defaults.
//

import Foundation
import SwiftUI

/// Strongly-typed wrapper around the keys we store in UserDefaults. Centralizing
/// the keys prevents typos and gives us one place to bump versions if a schema
/// migration is ever needed.
enum SettingsKey {
    /// Bookmark data (Data) for the user-selected save folder. We store a security-
    /// scoped bookmark so the folder reference survives across launches. For the
    /// unsandboxed v1 build we still use a bookmark — it costs nothing and makes
    /// the eventual sandboxed move cheap.
    static let saveFolderBookmark = "saveFolderBookmark"

    /// Plain-string fallback path. Used if the bookmark fails to resolve or the
    /// user hasn't picked a folder yet (we write the suggested default here on
    /// first launch).
    static let saveFolderPath = "saveFolderPath"

    /// Has the user been through first-run folder selection?
    static let didCompleteFirstRun = "didCompleteFirstRun"

    /// Filename template tokens. The actual template is a string with these
    /// placeholders: {date}, {time}, {slug}. See FileWriter.
    static let filenameTemplate = "filenameTemplate"

    /// Toggle: play dumptruck sound on save.
    static let soundEnabled = "soundEnabled"

    /// Toggle: launch Dumptruck at login.
    static let launchAtLogin = "launchAtLogin"

    /// Toggle: hide the menubar icon (shortcut-only mode).
    static let hideMenubarIcon = "hideMenubarIcon"

    /// Editor font name.
    static let editorFontName = "editorFontName"

    /// Editor font size.
    static let editorFontSize = "editorFontSize"

    /// Theme override: "system" | "light" | "dark".
    static let themeOverride = "themeOverride"

    /// Last known capture-window frame, stored as the system's NSStringFromRect
    /// representation so we can restore it across launches.
    static let lastWindowFrame = "lastWindowFrame"
}

/// Defaults that mirror the keys above. Any code reading a setting should fall
/// back to these — never hardcode a default at the call site.
enum SettingsDefaults {
    static let filenameTemplate = "{date}-{time}-{slug}"
    static let soundEnabled = true
    static let launchAtLogin = true
    static let hideMenubarIcon = false
    static let editorFontName = "SF Mono"
    static let editorFontSize: Double = 14
    static let themeOverride = "system"

    /// Default save folder under ~/Documents. Resolved lazily because Documents
    /// may not exist in some headless test contexts.
    static var suggestedSaveFolderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return docs.appendingPathComponent("Dumptruck", isDirectory: true)
    }
}

/// Lightweight read API. SwiftUI views should prefer @AppStorage, but non-View
/// code (FileWriter, DraftStore, AppDelegate) uses this.
struct SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    // MARK: - Save folder

    /// Resolves the user's chosen save folder. Tries the bookmark first
    /// (survives folder moves), then falls back to the stored path.
    /// Creates the directory if it doesn't exist.
    func resolveSaveFolder() -> URL? {
        if let bookmark = defaults.data(forKey: SettingsKey.saveFolderBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // Even though we're unsandboxed today, calling startAccessing is
                // harmless and makes the eventual move to sandbox cleaner.
                _ = url.startAccessingSecurityScopedResource()
                ensureDirectoryExists(url)
                return url
            }
        }
        if let path = defaults.string(forKey: SettingsKey.saveFolderPath) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            ensureDirectoryExists(url)
            return url
        }
        return nil
    }

    /// Stores the chosen folder both as a bookmark (preferred) and as a plain
    /// path (fallback / debugging).
    func setSaveFolder(_ url: URL) {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: SettingsKey.saveFolderBookmark)
        } else if let bookmark = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            // .withSecurityScope only works for sandboxed apps; this fallback
            // keeps the bookmark valid for our unsandboxed v1.
            defaults.set(bookmark, forKey: SettingsKey.saveFolderBookmark)
        }
        defaults.set(url.path, forKey: SettingsKey.saveFolderPath)
        defaults.set(true, forKey: SettingsKey.didCompleteFirstRun)
    }

    /// Has the user picked a folder yet?
    var didCompleteFirstRun: Bool {
        defaults.bool(forKey: SettingsKey.didCompleteFirstRun)
    }

    // MARK: - Other settings (read-only conveniences)

    var filenameTemplate: String {
        defaults.string(forKey: SettingsKey.filenameTemplate) ?? SettingsDefaults.filenameTemplate
    }

    var soundEnabled: Bool {
        defaults.bool(forKey: SettingsKey.soundEnabled)
    }

    var hideMenubarIcon: Bool {
        defaults.bool(forKey: SettingsKey.hideMenubarIcon)
    }

    var themeOverride: String {
        defaults.string(forKey: SettingsKey.themeOverride) ?? SettingsDefaults.themeOverride
    }

    // MARK: - Helpers

    private func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.filenameTemplate: SettingsDefaults.filenameTemplate,
            SettingsKey.soundEnabled: SettingsDefaults.soundEnabled,
            SettingsKey.launchAtLogin: SettingsDefaults.launchAtLogin,
            SettingsKey.hideMenubarIcon: SettingsDefaults.hideMenubarIcon,
            SettingsKey.editorFontName: SettingsDefaults.editorFontName,
            SettingsKey.editorFontSize: SettingsDefaults.editorFontSize,
            SettingsKey.themeOverride: SettingsDefaults.themeOverride,
        ])
    }

    private func ensureDirectoryExists(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
    }
}

/// Notification posted when the save folder changes, so observers (the file
/// writer, the status item tooltip, etc.) can refresh.
extension Notification.Name {
    static let dumptruckSaveFolderChanged = Notification.Name("DumptruckSaveFolderChanged")
    static let dumptruckHideMenubarIconChanged = Notification.Name("DumptruckHideMenubarIconChanged")
    static let dumptruckThemeOverrideChanged = Notification.Name("DumptruckThemeOverrideChanged")
}
