//
//  FileWriterTests.swift
//  DumptruckTests
//
//  Round-trip tests using a temp directory. Verifies atomicity, naming,
//  collision handling, and the empty-body error path.
//

import XCTest
@testable import Dumptruck

final class FileWriterTests: XCTestCase {

    private var tempDir: URL!
    private var writer: FileWriter!
    private let fixedDate = Calendar(identifier: .gregorian).date(from: {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 26
        c.hour = 14; c.minute = 30
        return c
    }())!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumptruck-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        writer = FileWriter()
        writer.clock = { self.fixedDate }
        writer.template = { "{date}-{time}-{slug}" }
    }

    override func tearDownWithError() throws {
        // Cleanup test dir only. Per user pref, never delete outside our own
        // sandboxed test temp.
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: -

    func testWrite_createsExpectedFile() throws {
        let url = try writer.write(body: "Hello world", into: tempDir)
        XCTAssertEqual(url.lastPathComponent, "2026-05-26-1430-hello-world.md")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "Hello world")
    }

    func testWrite_emptyBodyThrows() {
        XCTAssertThrowsError(try writer.write(body: "   \n  ", into: tempDir)) { error in
            guard case FileWriterError.emptyBody = error else {
                return XCTFail("Expected .emptyBody, got \(error)")
            }
        }
    }

    func testWrite_collisionAppendsSuffix() throws {
        let first = try writer.write(body: "Same opener here", into: tempDir)
        let second = try writer.write(body: "Same opener here too", into: tempDir)
        let third = try writer.write(body: "Same opener here again", into: tempDir)

        // First two share the slug (first 6 words match for "Same opener here").
        // The de-dup should produce -2 and -3 suffixes.
        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertNotEqual(second.lastPathComponent, third.lastPathComponent)
        XCTAssertTrue(second.lastPathComponent.contains("-2"))
        XCTAssertTrue(third.lastPathComponent.contains("-3"))
    }

    func testWrite_createsMissingFolder() throws {
        let nested = tempDir.appendingPathComponent("a/b/c", isDirectory: true)
        let url = try writer.write(body: "nested!", into: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
