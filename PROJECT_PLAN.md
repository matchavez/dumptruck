# Dumptruck — Project Plan (v1)

A native macOS menubar app for fast, Markdown-friendly text capture.

---

## 1. What we're building

A menubar-resident app called **Dumptruck**. Pressing a global shortcut (or clicking the menubar icon) opens a small floating editor. You type or paste — Markdown is syntax-highlighted as you go. Pressing **Return** saves the text as a `.md` file in a folder of your choice, plays a dumptruck sound, flashes a confirmation, and closes the window. Drafts persist between sessions so nothing is ever lost.

No Dock icon. No browser. No login. Just capture.

---

## 2. Confirmed decisions

| Area | Decision |
|---|---|
| **Language / UI** | Swift 5.9+, SwiftUI (with AppKit bridges where needed for `NSPanel`, `NSStatusItem`) |
| **Minimum macOS** | macOS 14 Sonoma |
| **App type** | Menubar-only (`LSUIElement = true`), no Dock icon |
| **Launch at login** | On by default; user-toggleable in Settings |
| **Global shortcut** | Default `⌘\` (cmd + backslash); fully configurable |
| **Window style** | Floating panel (`NSPanel`), remembers last screen position |
| **Editor** | Markdown syntax highlighting inline (no preview pane) |
| **Save key** | `Return` saves & closes; `Shift+Return` inserts newline |
| **Re-trigger** | Shortcut/click toggles window with a brief flash animation |
| **Menubar icon** | Left-click → opens window; right-click → menu (Settings, Quit) |
| **Save folder** | Single user-selected folder, set in Settings, changeable later |
| **Filename format** | `YYYY-MM-DD-HHMM-first-few-words.md` (user-customizable in Settings) |
| **Post-save** | Brief confirmation flash + dumptruck sound (sound toggleable) |
| **Unsaved text** | Auto-saved as a draft to disk; restored on next open |
| **Settings** | Save folder, global shortcut, launch-at-login, sound on/off, filename format, theme override, editor font/size, hide-menubar-icon option |
| **Dependencies** | `KeyboardShortcuts` (Sindre Sorhus, MIT). Sparkle deferred until we have code-signing. |
| **Icons** | SF Symbols (`truck.box`) for menubar; simple generated app icon |
| **Sound** | Bundled royalty-free dumptruck sound (CC0 / public-domain source) |
| **Distribution** | Personal use, unsigned, run locally for v1 |
| **Accessibility** | Full VoiceOver labels, keyboard-only operation, Dynamic Type, Reduce Motion respected, contrast ≥ WCAG 2.1 AA |

---

## 3. Architecture

A standard SwiftUI menubar app with a few AppKit escape hatches where SwiftUI alone is insufficient (global hotkeys, floating panels with custom behavior, menubar right-click menus).

```
Dumptruck.app
├── App layer            DumptruckApp.swift             @main, MenuBarExtra, scene wiring
├── Menubar              StatusItemController.swift     NSStatusItem + left/right click handling
├── Capture window       CapturePanel.swift             NSPanel subclass (floating, non-activating)
│                        CaptureWindowController.swift  Position memory, show/hide/toggle/flash
│                        CaptureView.swift              SwiftUI editor view
│                        MarkdownTextView.swift         NSTextView wrapper with syntax highlighting
├── Persistence          SettingsStore.swift            UserDefaults-backed @AppStorage settings
│                        DraftStore.swift               Auto-saved draft on disk
│                        FileWriter.swift               Filename templating + atomic file write
├── Shortcuts            ShortcutNames.swift            KeyboardShortcuts registration
├── Audio                SoundPlayer.swift              AVAudioPlayer wrapper, respects mute toggle
├── Settings UI          SettingsView.swift             Tabbed Settings scene
├── Resources            Assets.xcassets, Sounds/, Info.plist, Dumptruck.entitlements
└── Tests                DumptruckTests/                Unit tests for filename, draft, file writer
```

### Key technical choices and why

- **`NSPanel` (not SwiftUI `Window`) for the capture window** — SwiftUI's `Window` scene can't be made non-activating, can't float above full-screen apps cleanly, and doesn't remember position across launches reliably. An `NSPanel` with `.nonactivatingPanel` and `.utilityWindow` style gives us the Spotlight-like behavior we want.
- **`NSTextView` (wrapped) for the editor** — SwiftUI's `TextEditor` doesn't give us per-range attribute control needed for inline Markdown syntax highlighting on macOS 14. We use an `NSViewRepresentable` around `NSTextView` with a `NSTextStorage` delegate that re-highlights on edit.
- **`MenuBarExtra` vs `NSStatusItem`** — `MenuBarExtra` (SwiftUI) is nicer but doesn't expose right-click separately. We'll use `NSStatusItem` directly so we can route left-click to "toggle window" and right-click to a menu.
- **Drafts on disk** — saved to `~/Library/Application Support/Dumptruck/draft.md` on every keystroke (debounced 500 ms). Survives crashes and reboots.
- **Atomic save** — files are written to a temp file then renamed, so a crash mid-save can't produce a half-written note.

---

## 4. Accessibility plan

This is a first-class concern, not a polish step.

- **Keyboard-only operation**: every action reachable without the mouse. Tab order: editor → save button (implicit via Return) → cancel (implicit via Esc). Settings fully keyboard-navigable.
- **VoiceOver**: every control has an explicit `accessibilityLabel`. The editor announces "Markdown editor, [N] characters". Save announces "Saved to [filename]".
- **Dynamic Type**: editor font scales with the user's system text-size preference (with manual override in Settings).
- **Reduce Motion**: respects `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. The dismiss-flash animation is disabled (instant fade) when this is set.
- **Reduce Transparency**: the panel background uses a solid material when this is set.
- **Color contrast**: all text, icons, and focus indicators meet WCAG 2.1 AA contrast minimums in both light and dark modes. Verified with the macOS Accessibility Inspector before shipping.
- **No color-only signaling**: the save confirmation uses a checkmark glyph + motion + sound, not just a green flash.

---

## 5. macOS visual / interaction principles

- Vibrant material panel background (`.hudWindow` material) — feels native, blends with desktop and full-screen apps.
- Rounded corners, no custom chrome — the system gives us the right look.
- Menubar icon is monochrome SF Symbol, automatically templated for light/dark and tinted by the system.
- Standard macOS Settings scene (`Settings { ... }`) — opens with the standard `⌘,` shortcut and lives in the system menu bar's app menu when the capture window is focused.
- Standard macOS animations: spring for show, ease-out for dismiss, both ~150ms (or instant under Reduce Motion).
- Sound respects system volume and the Do Not Disturb / Focus state via `NSSound` (not `AVAudioPlayer` for sound effects — `NSSound` honors system mute properly).

---

## 6. Implementation milestones

I'll execute in this order so you can run the app earlier and see it come together:

**Milestone 1 — Skeleton (the app launches and lives in the menubar)**
- Xcode project scaffolding, `LSUIElement = true`, `NSStatusItem` with SF Symbol, right-click menu with "Quit". App appears in menubar, has no Dock icon.

**Milestone 2 — Capture window**
- `NSPanel` opens on left-click of menubar icon. Plain `NSTextView` inside. Position-memory across opens. Esc dismisses. Re-click toggles.

**Milestone 3 — Save flow**
- Settings scene with a folder picker. `Return` writes the text to that folder using the filename template. Brief confirmation flash on success.

**Milestone 4 — Global shortcut**
- `KeyboardShortcuts` integration. Default `⌘\`. Shortcut recorder in Settings.

**Milestone 5 — Markdown syntax highlighting**
- `NSTextStorage` delegate that styles headings, bold, italic, links, code, lists inline.

**Milestone 6 — Drafts and polish**
- Auto-save draft to disk on edit (debounced). Restore on next open. Toast flash animation. Dumptruck sound (bundled and triggered).

**Milestone 7 — Remaining Settings**
- Launch at login (ServiceManagement), sound toggle, theme override, font/size, filename template, hide-menubar-icon option.

**Milestone 8 — Accessibility and QA**
- VoiceOver pass, Reduce Motion pass, contrast verification, keyboard-only walkthrough, unit tests for filename/draft/file writer.

**Milestone 9 — Hand-off**
- README with build instructions, how to bypass Gatekeeper for unsigned local run, where settings/drafts live, troubleshooting.

I'll check in with you at the end of each milestone (or sooner if I hit a real decision point) rather than building all nine in one shot.

---

## 7. Open questions and risks I want to flag

1. **`⌘\` default shortcut** — works in most contexts, but Adobe apps and some browsers use it. If you have a different preferred default (e.g. `⌃⌥⌘Space`, `⌘⇧Space`), say so before I lock it in. Either way it's user-configurable.
2. **Sparkle deferred** — Sparkle requires a signed app to verify update integrity. Adding it to an unsigned local build is dead weight at best, a security footgun at worst. I'll wire the project structure so adding Sparkle later is one Swift Package away, but I won't include it in v1.
3. **Folder access and the sandbox** — running unsigned and unsandboxed for v1, this is a non-issue. If we later move to the Mac App Store, we'll need to add `com.apple.security.files.user-selected.read-write` and store a security-scoped bookmark for the save folder. I'll note this in the README so we're not surprised.
4. **Sourcing the dumptruck sound** — I'll search Freesound.org / Pixabay / archive.org for a CC0 or CC-BY clip. If I can't find something that sounds right, I'll fall back to a system sound and flag it for you to swap.
5. **Filename collisions** — if you save twice in the same minute with the same first few words (rare but possible), I'll append `-2`, `-3`, etc. rather than overwrite. Worth confirming this is what you want.
6. **First-word extraction for filenames** — I'll strip Markdown syntax (`#`, `*`, `-`, `>`), lowercase, replace whitespace with `-`, truncate to ~40 chars. Punctuation like `?` and `:` gets dropped. Example: `# Meeting Notes: Q3 Plan?` becomes `meeting-notes-q3-plan`. If you'd rather preserve the original case or punctuation, let me know.
7. **What is a "first few words"?** — I'm planning to use the first ~6 words or 40 characters, whichever comes first. Adjustable.

---

## 8. What I'd like from you before I start

Just a thumbs-up on this plan, plus answers (or "your call") on the open questions in §7. Once you green-light it, I'll start with Milestone 1 and check in as I go.
