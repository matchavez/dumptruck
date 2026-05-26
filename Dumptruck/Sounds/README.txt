Drop a sound file named `dumptruck.caf` (or .aiff, .wav, .m4a, .mp3) in
this folder and rebuild — SoundPlayer.swift will pick it up automatically.

This folder is wired into the Xcode project as a folder reference (blue
folder), so anything you put in here is bundled into the app's
Resources/Sounds/ directory at build time. No need to re-add files in Xcode.

Until a custom sound is present, Dumptruck falls back to the system "Tink"
sound on save. That fallback respects system mute / Focus.

Search Freesound.org or Pixabay for "dump truck" CC0 / CC-BY clips. Keep it
under 1.5 seconds so it doesn't trail into the next capture.
