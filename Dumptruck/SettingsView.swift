//
//  SettingsView.swift
//  Dumptruck
//
//  Tabbed Settings scene. macOS standard layout: a TabView with one section
//  per concern. Lives behind the system ⌘, shortcut and the right-click menu
//  "Settings…" item.
//
//  Tabs:
//    General   — save folder, filename template, sound, launch at login,
//                hide menubar icon, theme override
//    Shortcut  — KeyboardShortcuts recorder
//    Editor    — font + size
//    About     — credits + links
//

import SwiftUI
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")

            ShortcutSettingsTab()
                .tabItem { Label("Shortcut", systemImage: "command") }
                .tag("shortcut")

            EditorSettingsTab()
                .tabItem { Label("Editor", systemImage: "textformat") }
                .tag("editor")

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: 520, height: 360)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(SettingsKey.saveFolderPath) private var saveFolderPath: String = ""
    @AppStorage(SettingsKey.filenameTemplate) private var filenameTemplate: String = SettingsDefaults.filenameTemplate
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled: Bool = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.hideMenubarIcon) private var hideMenubarIcon: Bool = SettingsDefaults.hideMenubarIcon
    @AppStorage(SettingsKey.themeOverride) private var themeOverride: String = SettingsDefaults.themeOverride

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        Form {
            Section("Save location") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayPath)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel("Current save folder: \(displayPath)")
                        Text("Captured notes are written here as Markdown files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Choose…") { chooseFolder() }
                        .accessibilityHint("Pick a folder where Dumptruck saves new notes.")
                }
                .padding(.vertical, 2)
            }

            Section("Filename") {
                TextField("Template", text: $filenameTemplate)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityHint("Use {date}, {time}, and {slug} as placeholders.")
                Text("Tokens: \(FilenameTemplate.supportedTokens.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Preview: \(previewFilename).md")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Play sound on save", isOn: $soundEnabled)
                Toggle("Launch Dumptruck at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        let ok = LaunchAtLoginManager.setEnabled(newValue)
                        if !ok {
                            // Revert the UI if the system call failed.
                            launchAtLogin = LaunchAtLoginManager.isEnabled
                        }
                    }
                Toggle("Hide menubar icon (shortcut-only mode)", isOn: $hideMenubarIcon)
                    .onChange(of: hideMenubarIcon) { _, _ in
                        NotificationCenter.default.post(
                            name: .dumptruckHideMenubarIconChanged,
                            object: nil
                        )
                    }
            }

            Section("Appearance") {
                Picker("Theme", selection: $themeOverride) {
                    Text("Match system").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: themeOverride) { _, _ in
                    NotificationCenter.default.post(
                        name: .dumptruckThemeOverrideChanged,
                        object: nil
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var displayPath: String {
        if saveFolderPath.isEmpty {
            return "(not set — you'll be asked when you save your first note)"
        }
        return (saveFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private var previewFilename: String {
        FilenameTemplate.candidate(
            body: "# Meeting notes: Q3 plan?",
            date: Date(),
            template: filenameTemplate
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Dumptruck save folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let current = SettingsStore.shared.resolveSaveFolder() {
            panel.directoryURL = current
        } else {
            panel.directoryURL = SettingsDefaults.suggestedSaveFolderURL
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        SettingsStore.shared.setSaveFolder(url)
        NotificationCenter.default.post(name: .dumptruckSaveFolderChanged, object: nil)
    }
}

// MARK: - Shortcut

private struct ShortcutSettingsTab: View {
    var body: some View {
        Form {
            Section("Toggle capture") {
                KeyboardShortcuts.Recorder("Global shortcut:", name: .toggleCapture)
                    .accessibilityHint("Press the keys you want to use to open Dumptruck from anywhere.")
                Text("Default is ⌘\\ (Command + backslash). Click the field, then press your new combination. Click the × to clear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Editor

private struct EditorSettingsTab: View {
    @AppStorage(SettingsKey.editorFontName) private var editorFontName: String = SettingsDefaults.editorFontName
    @AppStorage(SettingsKey.editorFontSize) private var editorFontSize: Double = SettingsDefaults.editorFontSize

    private let fontChoices: [String] = [
        "SF Mono", "Menlo", "Monaco", "Courier New", "Helvetica Neue", "SF Pro Text"
    ]

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $editorFontName) {
                    ForEach(fontChoices, id: \.self) { Text($0).tag($0) }
                }
                Stepper(
                    value: $editorFontSize,
                    in: 10...24,
                    step: 1
                ) {
                    Text("Size: \(Int(editorFontSize)) pt")
                }
                .accessibilityValue("\(Int(editorFontSize)) points")

                // Live preview chip.
                Text("The quick brown fox 🦊 # heading **bold**")
                    .font(.custom(editorFontName, size: editorFontSize))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "truck.box.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Dumptruck")
                .font(.title2.bold())
            Text("Quick capture for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Text("v\(appVersion) (\(buildNumber))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("© 2026 Mat Chavez")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
