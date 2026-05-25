//
//  MarkdownHighlighter.swift
//  Dumptruck
//
//  NSTextStorageDelegate that re-styles the editor's text storage on every edit
//  to give us inline Markdown syntax highlighting. We do NOT render Markdown —
//  the source stays visible. We just give headings/bold/italic/etc. distinct
//  font weights, colors, or sizes so the user can see structure as they type.
//
//  Performance: NSTextStorage's processEditing notification gives us the
//  `editedRange` and a margin around it, but for the typical short notes
//  Dumptruck captures (a few hundred chars), re-styling the whole storage on
//  each edit is fast enough and dramatically simpler than incremental edits.
//  If profiling shows a hot spot here, switch to line-by-line scoping using
//  textStorage.editedRange.
//

import AppKit

final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    /// Base font used as the starting point for every styled range. The
    /// highlighter swaps weight/size off this — never reaches for a hardcoded
    /// face — so user font preferences flow through.
    var baseFont: NSFont

    init(font: NSFont) {
        self.baseFont = font
        super.init()
    }

    // MARK: - NSTextStorageDelegate

    /// Called after the storage finishes processing an edit. This is the right
    /// hook (not `willProcessEditing`) because by `didProcessEditing` the
    /// length and contents are final.
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Only react to attribute-changing edits. Ignore pure attribute edits
        // (those are our own changes) to avoid an infinite loop.
        guard editedMask.contains(.editedCharacters) else { return }

        // Re-style the whole document. See note above about scope.
        highlight(textStorage)
    }

    // MARK: - Highlighting

    /// Apply syntax styling to the entire storage. Public so we can force a
    /// re-style after font changes / draft restoration.
    func highlight(_ storage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        // We need to call beginEditing/endEditing so layout managers batch the
        // attribute changes and don't re-layout on every setAttributes call.
        storage.beginEditing()
        defer { storage.endEditing() }

        // Wipe to baseline first. Without this, removed markup would keep its
        // old styling.
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        let text = storage.string as NSString

        // Headings: # H1, ## H2, ### H3, up to 6.
        applyRegex(headingRegex, to: storage, text: text, range: fullRange) { match in
            guard match.numberOfRanges >= 3 else { return [:] }
            let hashRange = match.range(at: 1)
            let bodyRange = match.range(at: 2)
            let level = max(1, min(6, hashRange.length))
            let sizeBump: CGFloat = [0, 8, 6, 4, 2, 1, 0][level]
            let headingFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: self.baseFont.pointSize + sizeBump, weight: .bold),
                toHaveTrait: .boldFontMask
            )
            // Hash glyph: lighter weight, secondary color, so it reads as syntax.
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: self.baseFont.pointSize + sizeBump, weight: .regular),
            ], range: hashRange)
            // Heading body: bold, slightly larger.
            storage.addAttributes([
                .font: headingFont,
                .foregroundColor: NSColor.labelColor,
            ], range: bodyRange)
            return [:]
        }

        // Bold: **text** or __text__.
        applyInline(
            boldRegex,
            to: storage,
            range: fullRange,
            inner: { range in
                let bold = NSFontManager.shared.convert(self.baseFont, toHaveTrait: .boldFontMask)
                storage.addAttributes([.font: bold], range: range)
            }
        )

        // Italic: *text* or _text_. Careful: ** is bold; the regex below is
        // anchored to single asterisks/underscores not adjacent to another.
        applyInline(
            italicRegex,
            to: storage,
            range: fullRange,
            inner: { range in
                let italic = NSFontManager.shared.convert(self.baseFont, toHaveTrait: .italicFontMask)
                storage.addAttributes([.font: italic], range: range)
            }
        )

        // Inline code: `code` and triple-backtick code blocks.
        applyRegex(inlineCodeRegex, to: storage, text: text, range: fullRange) { match in
            let codeFont = NSFont.monospacedSystemFont(ofSize: self.baseFont.pointSize, weight: .regular)
            storage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.systemPink,
            ], range: match.range)
            return [:]
        }

        applyRegex(codeBlockRegex, to: storage, text: text, range: fullRange) { match in
            let codeFont = NSFont.monospacedSystemFont(ofSize: self.baseFont.pointSize, weight: .regular)
            storage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.systemTeal,
            ], range: match.range)
            return [:]
        }

        // Links: [text](url)
        applyRegex(linkRegex, to: storage, text: text, range: fullRange) { match in
            guard match.numberOfRanges >= 3 else { return [:] }
            storage.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: match.range(at: 1))
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: match.range(at: 2))
            return [:]
        }

        // List markers: -, *, +, or `1. ` at the start of a line. Just dim the marker.
        applyRegex(listMarkerRegex, to: storage, text: text, range: fullRange) { match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
            ], range: match.range)
            return [:]
        }

        // Block quotes: > at line start.
        applyRegex(blockQuoteRegex, to: storage, text: text, range: fullRange) { match in
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: match.range)
            return [:]
        }
    }

    // MARK: - Regex helpers

    private func applyRegex(
        _ regex: NSRegularExpression,
        to storage: NSTextStorage,
        text: NSString,
        range: NSRange,
        body: (NSTextCheckingResult) -> [NSAttributedString.Key: Any]
    ) {
        regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
            guard let match else { return }
            _ = body(match)
        }
    }

    /// Convenience for inline emphasis (bold/italic): finds matches, applies the
    /// `inner` style to the inner content range (group 1), and dims the
    /// delimiters.
    private func applyInline(
        _ regex: NSRegularExpression,
        to storage: NSTextStorage,
        range: NSRange,
        inner: (NSRange) -> Void
    ) {
        let nsText = storage.string as NSString
        regex.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            inner(match.range(at: 1))
            // Dim the delimiter(s) — outer match minus inner content.
            let outer = match.range
            let innerR = match.range(at: 1)
            if innerR.location > outer.location {
                let leading = NSRange(
                    location: outer.location,
                    length: innerR.location - outer.location
                )
                if leading.length > 0 {
                    storage.addAttributes([
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ], range: leading)
                }
            }
            let trailingStart = innerR.location + innerR.length
            let outerEnd = outer.location + outer.length
            if outerEnd > trailingStart {
                let trailing = NSRange(
                    location: trailingStart,
                    length: outerEnd - trailingStart
                )
                if trailing.length > 0 {
                    storage.addAttributes([
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ], range: trailing)
                }
            }
            _ = nsText // silence unused warning
        }
    }

    // MARK: - Patterns
    //
    // All anchored with multiline mode so `^` works per-line.

    private let headingRegex = try! NSRegularExpression(
        pattern: #"^(#{1,6})\s+(.+)$"#,
        options: [.anchorsMatchLines]
    )

    private let boldRegex = try! NSRegularExpression(
        // **text** or __text__, lazy so ** ** ** doesn't collapse into one giant match.
        pattern: #"(?:\*\*|__)(.+?)(?:\*\*|__)"#,
        options: []
    )

    private let italicRegex = try! NSRegularExpression(
        // Single * or _ surrounding non-empty content, not part of a double delimiter.
        pattern: #"(?<![\*_])[\*_]([^\*_\n]+?)[\*_](?![\*_])"#,
        options: []
    )

    private let inlineCodeRegex = try! NSRegularExpression(
        pattern: #"`[^`\n]+`"#,
        options: []
    )

    private let codeBlockRegex = try! NSRegularExpression(
        pattern: "```[\\s\\S]*?```",
        options: []
    )

    private let linkRegex = try! NSRegularExpression(
        pattern: #"(\[[^\]]+\])(\([^\)]+\))"#,
        options: []
    )

    private let listMarkerRegex = try! NSRegularExpression(
        pattern: #"^\s*([-*+]|\d+\.)\s"#,
        options: [.anchorsMatchLines]
    )

    private let blockQuoteRegex = try! NSRegularExpression(
        pattern: #"^\s*>"#,
        options: [.anchorsMatchLines]
    )
}
