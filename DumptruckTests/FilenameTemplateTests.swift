//
//  FilenameTemplateTests.swift
//  DumptruckTests
//
//  Pure unit tests for FilenameTemplate. No FileManager / disk access.
//

import XCTest
@testable import Dumptruck

final class FilenameTemplateTests: XCTestCase {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        comps.hour = h; comps.minute = mi
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    // MARK: - candidate(...)

    func testCandidate_defaultTemplate() {
        let name = FilenameTemplate.candidate(
            body: "Meeting with Jane",
            date: date(2026, 5, 26, 14, 30),
            template: "{date}-{time}-{slug}"
        )
        XCTAssertEqual(name, "2026-05-26-1430-meeting-with-jane")
    }

    func testCandidate_stripsMarkdownAndPunctuation() {
        let name = FilenameTemplate.candidate(
            body: "# Meeting Notes: Q3 Plan?",
            date: date(2026, 1, 2, 9, 5),
            template: "{date}-{time}-{slug}"
        )
        XCTAssertEqual(name, "2026-01-02-0905-meeting-notes-q3-plan")
    }

    func testCandidate_emptySlugFallback() {
        let name = FilenameTemplate.candidate(
            body: "",
            date: date(2026, 5, 26, 14, 30),
            template: "{slug}"
        )
        XCTAssertEqual(name, "2026-05-26-1430-note")
    }

    func testCandidate_takesFirstNonEmptyLineOnly() {
        let name = FilenameTemplate.candidate(
            body: "\n\nFirst real line here\nSecond line should not appear",
            date: date(2026, 5, 26, 14, 30),
            template: "{slug}"
        )
        XCTAssertEqual(name, "first-real-line-here")
    }

    // MARK: - slugify(...)

    func testSlugify_truncatesAt40Chars() {
        let input = "a really long sentence that just keeps going and going forever past forty characters"
        let slug = FilenameTemplate.slugify(input)
        XCTAssertLessThanOrEqual(slug.count, 40)
        XCTAssertFalse(slug.hasSuffix("-"))
    }

    func testSlugify_capsAt6Words() {
        let slug = FilenameTemplate.slugify("one two three four five six seven eight")
        XCTAssertEqual(slug, "one-two-three-four-five-six")
    }

    func testSlugify_dropsEmptyAfterStripping() {
        XCTAssertEqual(FilenameTemplate.slugify("###"), "")
        XCTAssertEqual(FilenameTemplate.slugify("?!"), "")
    }

    func testSlugify_collapsesMultipleDashes() {
        // Input punctuation-heavy: "Q3 -- !? plan"
        let slug = FilenameTemplate.slugify("Q3 -- !? plan")
        XCTAssertFalse(slug.contains("--"))
        XCTAssertTrue(slug.contains("q3"))
        XCTAssertTrue(slug.contains("plan"))
    }

    // MARK: - disambiguate(...)

    func testDisambiguate_returnsCandidateWhenFree() {
        let chosen = FilenameTemplate.disambiguate(
            candidate: "2026-05-26-1430-note",
            existingNames: ["other-file"]
        )
        XCTAssertEqual(chosen, "2026-05-26-1430-note")
    }

    func testDisambiguate_appendsTwoOnCollision() {
        let chosen = FilenameTemplate.disambiguate(
            candidate: "note",
            existingNames: ["note"]
        )
        XCTAssertEqual(chosen, "note-2")
    }

    func testDisambiguate_picksNextAvailableIndex() {
        let chosen = FilenameTemplate.disambiguate(
            candidate: "note",
            existingNames: ["note", "note-2", "note-3"]
        )
        XCTAssertEqual(chosen, "note-4")
    }
}
