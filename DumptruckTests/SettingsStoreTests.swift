//
//  SettingsStoreTests.swift
//  DumptruckTests
//
//  Tests the SettingsStore against a private UserDefaults suite so the user's
//  real preferences are never touched.
//

import XCTest
@testable import Dumptruck

final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!
    private var tempFolder: URL!

    override func setUpWithError() throws {
        suiteName = "dumptruck-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults, "Could not create test UserDefaults suite")
        store = SettingsStore(defaults: defaults)

        tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumptruck-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempFolder)
    }

    // MARK: - Defaults registration

    func testDefaults_areRegisteredAtConstruction() {
        XCTAssertEqual(store.filenameTemplate, SettingsDefaults.filenameTemplate)
        XCTAssertTrue(store.soundEnabled)
        XCTAssertFalse(store.hideMenubarIcon)
        XCTAssertEqual(store.themeOverride, "system")
    }

    // MARK: - Save folder round-trip

    func testSetSaveFolder_persistsPathAndCompletesFirstRun() {
        XCTAssertFalse(store.didCompleteFirstRun)
        store.setSaveFolder(tempFolder)
        XCTAssertTrue(store.didCompleteFirstRun)
        let resolved = store.resolveSaveFolder()
        XCTAssertEqual(resolved?.path, tempFolder.path)
    }

    func testResolveSaveFolder_returnsNilWhenUnset() {
        XCTAssertNil(store.resolveSaveFolder())
    }

    func testResolveSaveFolder_recreatesMissingDirectory() throws {
        store.setSaveFolder(tempFolder)
        try FileManager.default.removeItem(at: tempFolder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFolder.path))

        let resolved = store.resolveSaveFolder()
        XCTAssertNotNil(resolved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved!.path))
    }

    // MARK: - Notifications

    func testNotificationName_constantsAreStable() {
        // Smoke test: the names are referenced by string from observers in
        // AppDelegate / CaptureWindowController; if anyone changes the raw
        // strings, observers silently break. Pin them here.
        XCTAssertEqual(Notification.Name.dumptruckSaveFolderChanged.rawValue,
                       "DumptruckSaveFolderChanged")
        XCTAssertEqual(Notification.Name.dumptruckHideMenubarIconChanged.rawValue,
                       "DumptruckHideMenubarIconChanged")
        XCTAssertEqual(Notification.Name.dumptruckThemeOverrideChanged.rawValue,
                       "DumptruckThemeOverrideChanged")
    }
}
