//
//  FilenameTemplate.swift
//  Dumptruck
//
//  Pure function: (body, date, template, existing files) → safe filename.
//  No side effects, no FileManager access — that lives in FileWriter so this
//  is unit-testable in isolation.
//

import Foundation

enum FilenameTemplate {

    /// Tokens the template understands.
    ///   {date}  → 2026-05-26
    ///   {time}  → 1430
    ///   {slug}  → first-few-words-of-the-note
    static let supportedTokens = ["{date}", "{time}", "{slug}"]

    /// Builds a candidate filename (without the `.md` extension) from the body
    /// and a given date. Pure; no disk access.
    ///
    /// Slug rules (locked in with Mat in PROJECT_PLAN §7):
    ///   - Strip Markdown syntax: # * - > _ ` [ ] ( )
    ///   - Strip punctuation: ? : , . ! ; "  '
    ///   - Lowercase
    ///   - Whitespace collapses to a single `-`
    ///   - Truncate to ~40 chars OR 6 words, whichever comes first
    static func candidate(
        body: String,
        date: Date,
        template: String
    ) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let dateComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        let datePart = String(
            format: "%04d-%02d-%02d",
            dateComps.year ?? 1970,
            dateComps.month ?? 1,
            dateComps.day ?? 1
        )
        let timePart = String(
            format: "%02d%02d",
            dateComps.hour ?? 0,
            dateComps.minute ?? 0
        )
        let slug = slugify(body)

        var rendered = template
        rendered = rendered.replacingOccurrences(of: "{date}", with: datePart)
        rendered = rendered.replacingOccurrences(of: "{time}", with: timePart)
        rendered = rendered.replacingOccurrences(of: "{slug}", with: slug)

        // If the resulting name is empty (template was all whitespace, or slug
        // was empty and the template was just `{slug}`), fall back to a
        // timestamped default so we never produce ".md".
        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(datePart)-\(timePart)-note"
        }
        return trimmed
    }

    /// Resolves collisions by appending `-2`, `-3`, ... until an unused name
    /// is found. Returns the chosen name (no extension).
    ///
    /// `existingNames` should be the set of base filenames (no extension)
    /// already in the destination directory. Caller is responsible for
    /// gathering this — typically by listing the directory once.
    static func disambiguate(
        candidate: String,
        existingNames: Set<String>
    ) -> String {
        if !existingNames.contains(candidate) {
            return candidate
        }
        var n = 2
        while existingNames.contains("\(candidate)-\(n)") {
            n += 1
            if n > 9999 {
                // Pathological case; give up and tack on a UUID slice.
                return "\(candidate)-\(UUID().uuidString.prefix(6).lowercased())"
            }
        }
        return "\(candidate)-\(n)"
    }

    // MARK: - Slug

    /// Markdown syntax characters we strip from the slug.
    private static let markdownChars = CharacterSet(charactersIn: "#*->_`[]()")

    /// Punctuation we drop entirely (not converted to `-`).
    private static let droppedPunctuation = CharacterSet(charactersIn: "?:,.!;\"'")

    static func slugify(
        _ input: String,
        maxChars: Int = 40,
        maxWords: Int = 6
    ) -> String {
        // Take only the first non-empty line — captions in second paragraphs
        // shouldn't bleed into the filename.
        let firstLine = input
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? input

        // Pass 1: strip Markdown + punctuation.
        var cleaned = String(firstLine.unicodeScalars.filter { scalar in
            !markdownChars.contains(scalar) && !droppedPunctuation.contains(scalar)
        })

        // Pass 2: lowercase.
        cleaned = cleaned.lowercased()

        // Pass 3: collapse whitespace into single `-`.
        cleaned = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        // Pass 4: drop any character that's not alphanumeric, dash, or
        // underscore. Belt-and-suspenders for unicode oddities.
        cleaned = String(cleaned.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
        })

        // Pass 5: collapse runs of `-` and trim leading/trailing dashes.
        while cleaned.contains("--") {
            cleaned = cleaned.replacingOccurrences(of: "--", with: "-")
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Pass 6: word cap.
        let words = cleaned.split(separator: "-")
        if words.count > maxWords {
            cleaned = words.prefix(maxWords).joined(separator: "-")
        }

        // Pass 7: char cap. Cut at a word boundary if possible.
        if cleaned.count > maxChars {
            let limit = cleaned.index(cleaned.startIndex, offsetBy: maxChars)
            let truncated = String(cleaned[..<limit])
            // Trim trailing dash from the cut, if any.
            cleaned = truncated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return cleaned
    }
}
