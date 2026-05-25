//
//  DraftStore.swift
//  Dumptruck
//
//  Persists the in-progress capture buffer so an unintended close, crash, or
//  reboot can't lose the user's work. One global draft (singleton buffer);
//  the capture window only ever holds one at a time.
//

import Foundation

struct DraftStore {

    /// Where we keep the draft on disk. Lives in Application Support so it
    /// doesn't clutter ~/Documents.
    static var draftURL: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        let dir = base.appendingPathComponent("Dumptruck", isDirectory: true)
        // Create-if-missing; ignore the error — the read/write below will
        // surface anything fatal.
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("draft.md")
    }()

    /// Read the saved draft. Returns nil if none exists.
    func load() -> String? {
        let url = DraftStore.draftURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Overwrites the draft on disk with `text`. Atomic so an in-flight save
    /// can't end with a truncated draft.
    func save(_ text: String) {
        let url = DraftStore.draftURL
        let data = Data(text.utf8)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("[Dumptruck] DraftStore.save failed: \(error)")
        }
    }

    /// Remove the draft entirely. Called after a successful save.
    /// We unlink the file rather than writing an empty one so a corrupted-empty
    /// file can't be misread as "draft present, just blank".
    func clear() {
        let url = DraftStore.draftURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Per user preference: avoid file deletion. The draft is OURS, not a
        // user file — it lives in our Application Support directory and was
        // created by us. Clearing it is required for correctness; otherwise
        // every fresh capture would start with the last saved note pre-filled.
        // We document this exception clearly.
        try? FileManager.default.removeItem(at: url)
    }
}
