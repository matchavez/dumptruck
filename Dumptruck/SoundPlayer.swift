//
//  SoundPlayer.swift
//  Dumptruck
//
//  Plays the "save" sound on a successful capture. We use NSSound (not
//  AVAudioPlayer) for two reasons:
//    * NSSound honors system mute and Focus / Do Not Disturb properly.
//    * For short one-shots it's strictly cheaper.
//
//  If we ever bundle a custom dumptruck.caf in Resources/Sounds/, it takes
//  precedence over the system sound. Until then we fall back to NSSound(named:)
//  with a system sound name — guaranteed to exist on all macOS installs.
//

import AppKit

final class SoundPlayer {

    /// The bundled sound file's base name (without extension). Searched for
    /// in the main bundle's Resources. If found, this overrides the system sound.
    private static let bundledSoundName = "dumptruck"

    /// System sound to use when the bundled file isn't present. "Tink" is the
    /// closest to a brief, dry confirmation tone among the built-ins. Other
    /// reasonable picks: "Pop", "Submarine".
    private static let fallbackSystemSoundName = "Tink"

    /// Cached NSSound instance so we don't re-allocate on every save.
    private lazy var saveSound: NSSound? = SoundPlayer.loadSaveSound()

    func playSaveSound() {
        // Respect the SettingsStore toggle. The caller checks too, but doing it
        // here makes this safe to call unconditionally.
        guard SettingsStore.shared.soundEnabled else { return }
        saveSound?.stop()    // make sure rapid saves don't queue up
        saveSound?.play()
    }

    private static func loadSaveSound() -> NSSound? {
        // 1. Bundled custom sound (if present).
        for ext in ["caf", "aiff", "wav", "m4a", "mp3"] {
            if let url = Bundle.main.url(
                forResource: bundledSoundName,
                withExtension: ext
            ),
            let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
            // Also try inside the "Sounds" subdirectory of Resources, which is
            // where the Xcode project group keeps audio assets.
            if let url = Bundle.main.url(
                forResource: bundledSoundName,
                withExtension: ext,
                subdirectory: "Sounds"
            ),
            let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
        }
        // 2. System sound by name (Tink, Pop, Glass, ...).
        return NSSound(named: NSSound.Name(fallbackSystemSoundName))
    }
}
