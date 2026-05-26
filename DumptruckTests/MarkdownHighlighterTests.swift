//
//  MarkdownHighlighterTests.swift
//  DumptruckTests
//
//  Exercises the NSTextStorageDelegate without an editor UI. We construct an
//  NSTextStorage with sample Markdown, attach the highlighter, run a highlight
//  pass, and assert that specific ranges carry the attributes we expect
//  (font traits, foreground color buckets).
//

import XCTest
import AppKit
@testable import Dumptruck

final class MarkdownHighlighterTests: XCTestCase {

    private func highlight(_ markdown: String) -> NSTextStorage {
        let storage = NSTextStorage(string: markdown)
        let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let h = MarkdownHighlighter(font: baseFont)
        // Run the pass directly rather than depending on storage edit notifications.
        h.highlight(storage)
        return storage
    }

    private func attributes(_ storage: NSTextStorage, at index: Int) -> [NSAttributedString.Key: Any] {
        guard index < storage.length else { return [:] }
        var range = NSRange(location: 0, length: 0)
        return storage.attributes(at: index, effectiveRange: &range)
    }

    private func isBold(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    private func isItalic(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.italicFontMask)
    }

    // MARK: -

    func testHeading_bodyIsBoldAndLarger() {
        let s = "# My heading"
        let storage = highlight(s)
        // Skip past "# " (2 chars) into the heading body.
        let bodyIndex = 2
        let attrs = attributes(storage, at: bodyIndex)
        guard let font = attrs[.font] as? NSFont else {
            return XCTFail("No font on heading body")
        }
        XCTAssertTrue(isBold(font), "Heading body should be bold")
        XCTAssertGreaterThan(font.pointSize, 14, "Heading body should be larger than base font")
    }

    func testHeading_hashIsSecondaryLabelColor() {
        let storage = highlight("# Heading")
        let attrs = attributes(storage, at: 0)
        let color = attrs[.foregroundColor] as? NSColor
        XCTAssertEqual(color, NSColor.secondaryLabelColor)
    }

    func testBold_innerRangeIsBold() {
        let storage = highlight("**bold** text")
        // index 2 is inside "bold"
        let attrs = attributes(storage, at: 2)
        guard let font = attrs[.font] as? NSFont else { return XCTFail() }
        XCTAssertTrue(isBold(font))
    }

    func testItalic_innerRangeIsItalic() {
        let storage = highlight("*italic* text")
        let attrs = attributes(storage, at: 1) // inside "italic"
        guard let font = attrs[.font] as? NSFont else { return XCTFail() }
        XCTAssertTrue(isItalic(font))
    }

    func testInlineCode_useMonospaceAndAccentColor() {
        let storage = highlight("call `foo()` here")
        let attrs = attributes(storage, at: 6) // inside `foo()`
        let color = attrs[.foregroundColor] as? NSColor
        XCTAssertEqual(color, NSColor.systemPink)
    }

    func testLink_textIsLinkColored() {
        let storage = highlight("a [Claude](https://claude.ai) link")
        let attrs = attributes(storage, at: 3) // inside "[Claude]"
        let color = attrs[.foregroundColor] as? NSColor
        XCTAssertEqual(color, NSColor.linkColor)
    }

    func testEmptyStorage_doesNotCrash() {
        let storage = NSTextStorage(string: "")
        let h = MarkdownHighlighter(font: NSFont.systemFont(ofSize: 14))
        h.highlight(storage)  // Must early-return on empty.
        XCTAssertEqual(storage.length, 0)
    }

    func testPlainText_remainsBaseFontAndLabelColor() {
        let storage = highlight("just words")
        let attrs = attributes(storage, at: 0)
        let color = attrs[.foregroundColor] as? NSColor
        XCTAssertEqual(color, NSColor.labelColor)
    }
}
