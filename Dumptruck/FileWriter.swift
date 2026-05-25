//
//  FileWriter.swift
//  Dumptruck
//
//  Writes captured text to a .md file in the user's chosen save folder.
//  Uses an atomic write (temp file + rename) so a crash mid-write can never
//  leave a half-baked note on disk.
//

import Foundation

enum FileWriterError: LocalizedError {
    case emptyBody
    case folderNotWritable(URL)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emptyBody:
            return "Nothing to save — the editor is empty."
        case .folderNotWritable(let url):
            return "Can't write to “\(url.lastPathComponent)”."
        case .writeFailed(let underlying):
            return "Save failed: \(underlying.localizedDescription)"
        }
    }
}

struct FileWriter {

    /// Clock injected so tests can pin to a known instant. Defaults to real time.
    var clock: () -> Date = { Date() }

    /// Filename template; defaults to whatever the user has configured.
    var template: () -> String = { SettingsStore.shared.filenameTemplate }

    /// Writes `body` to a new file inside `folder`. Returns the final URL.
    /// Atomic: writes to a temp file then renames into place.
    func write(body: String, into folder: URL) throws -> URL {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FileWriterError.emptyBody
        }

        // Ensure the folder exists. resolveSaveFolder() already does this,
        // but be defensive in case the folder was deleted between checks.
        if !FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )
            } catch {
                throw FileWriterError.folderNotWritable(folder)
            }
        }

        // Build candidate filename and disambiguate against existing files.
        let candidate = FilenameTemplate.candidate(
            body: body,
            date: clock(),
            template: template()
        )
        let existing = existingBaseNames(in: folder)
        let finalBase = FilenameTemplate.disambiguate(
            candidate: candidate,
            existingNames: existing
        )
        let finalURL = folder.appendingPathComponent("\(finalBase).md")

        // Atomic write: NSData (via Data) supports `.atomic` which does the
        // tmp-file + rename dance internally.
        do {
            let data = Data(body.utf8)
            try data.write(to: finalURL, options: [.atomic])
        } catch {
            throw FileWriterError.writeFailed(underlying: error)
        }

        return finalURL
    }

    /// Lists the .md files in the folder and returns their base names (no
    /// extension). Used by disambiguation. Failure is treated as "empty
    /// folder" — we don't want a directory-read error to abort a save.
    private func existingBaseNames(in folder: URL) -> Set<String> {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Set(
            contents
                .filter { $0.pathExtension.lowercased() == "md" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )
    }
}
