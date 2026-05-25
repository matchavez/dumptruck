//
//  DraftStoreTests.swift
//  DumptruckTests
//
//  Note: DraftStore currently uses a fixed Application Support path. These
//  tests swap that path to a temp directory before each test by injecting a
//  custom URL via the static `draftURL` property. Tests should NOT touch the
//  user's real draft.
//

import XCTest
@testable import Dumptruck

final class DraftStoreTests: XCTestCase {

    private var originalURL: URL!
    private var testURL: URL!

    override func setUpWithError() throws {
        originalURL = DraftStore.draftURL
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumptruck-draft-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        testURL = dir.appendingPathComponent("draft.md")
        DraftStore.draftURL = testURL
    }

    override func tearDownWithError() throws {
        // Restore the real default so other tests don't leak.
        DraftStore.draftURL = originalURL
        try? FileManager.default.removeItem(at: testURL.deletingLastPathComponent())
    }

    func testSaveAndLoad_roundTrip() {
        let store = DraftStore()
        XCTAssertNil(store.load())
        store.save("# A draft note\nwith multiple lines")
        XCTAssertEqual(store.load(), "# A draft note\nwith multiple lines")
    }

    func testClear_removesDraft() {
        let store = DraftStore()
        store.save("about to disappear")
        XCTAssertNotNil(store.load())
        store.clear()
        XCTAssertNil(store.load())
    }

    func testClear_isNoOpWhenAbsent() {
        let store = DraftStore()
        // Should not crash even when no draft on disk.
        store.clear()
        XCTAssertNil(store.load())
    }
}
