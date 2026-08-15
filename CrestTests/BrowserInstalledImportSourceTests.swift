import Foundation
import SQLite3
import XCTest
@testable import Crest

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class BrowserInstalledImportSourceTests: XCTestCase {
    func testIsolatedLaunchRejectsSafeStorageBeforeKeychainAccess() {
        XCTAssertThrowsError(
            try LaunchScopedBrowserSafeStorage().secret(for: .chrome)
        ) { error in
            XCTAssertEqual(
                error as? BrowserPasswordImportError,
                .safeStorageUnavailable
            )
        }
    }

    func testRememberedBrowserAccessIsStoredSeparatelyForEachBrowser() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcBookmark = Data("arc-bookmark".utf8)
        let zenBookmark = Data("zen-bookmark".utf8)

        BrowserImportAccessStore.saveBookmarkData(
            arcBookmark,
            for: .arc,
            defaults: defaults
        )
        BrowserImportAccessStore.saveBookmarkData(
            zenBookmark,
            for: .zen,
            defaults: defaults
        )

        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .arc, defaults: defaults),
            arcBookmark
        )
        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .zen, defaults: defaults),
            zenBookmark
        )
        XCTAssertNil(
            BrowserImportAccessStore.bookmarkData(for: .chrome, defaults: defaults)
        )
    }

    func testClearingRememberedAccessOnlyClearsTheRequestedBrowser() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcBookmark = Data("arc-bookmark".utf8)
        let zenBookmark = Data("zen-bookmark".utf8)
        BrowserImportAccessStore.saveBookmarkData(
            arcBookmark,
            for: .arc,
            defaults: defaults
        )
        BrowserImportAccessStore.saveBookmarkData(
            zenBookmark,
            for: .zen,
            defaults: defaults
        )

        BrowserImportAccessStore.clear(for: .arc, defaults: defaults)

        XCTAssertNil(
            BrowserImportAccessStore.bookmarkData(for: .arc, defaults: defaults)
        )
        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .zen, defaults: defaults),
            zenBookmark
        )
    }

    func testRememberedDataDirectoryResolvesForARepeatImport() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: directory) }

        try BrowserImportAccessStore.remember(
            directory,
            for: .arc,
            defaults: defaults
        )
        let access = try XCTUnwrap(
            BrowserImportAccessStore.resolve(for: .arc, defaults: defaults)
        )
        defer { access.stopAccessing() }

        XCTAssertEqual(
            access.url.resolvingSymlinksInPath(),
            directory.resolvingSymlinksInPath()
        )
    }

    func testHostHomeResolutionPrefersTheAccountHomeOverASandboxContainer() {
        let containerHome = URL(fileURLWithPath: "/Users/test/Library/Containers/app/Data")
        let accountHome = URL(fileURLWithPath: "/Users/test")

        XCTAssertEqual(
            BrowserImportDataLocator.resolvedHomeDirectory(
                currentHome: containerHome,
                accountHome: accountHome
            ),
            accountHome
        )
        XCTAssertEqual(
            BrowserImportDataLocator.resolvedHomeDirectory(
                currentHome: containerHome,
                accountHome: nil
            ),
            containerHome
        )
    }

    func testLocatorFindsArcSidebarAtItsStableApplicationSupportPath() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sidebar = home.appendingPathComponent(
            "Library/Application Support/Arc/StorableSidebar.json"
        )
        try createFixture(at: sidebar)

        XCTAssertEqual(
            BrowserImportDataLocator.latestImportURL(for: .arc, homeDirectory: home),
            sidebar
        )
    }

    func testSelectedArcDataDirectoryFindsTheSidebarWithoutAHomePath() throws {
        let root = try makeTemporaryHome().appendingPathComponent("Arc")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let sidebar = root.appendingPathComponent("StorableSidebar.json")
        try createFixture(at: sidebar)

        let profiles = BrowserImportDataLocator.importProfiles(
            for: .arc,
            dataDirectory: root
        )

        XCTAssertEqual(profiles.map(\.sessionURL), [sidebar])
    }

    func testLocatorChoosesNewestZenProfileSession() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let first = home.appendingPathComponent(
            "Library/Application Support/zen/Profiles/first/zen-sessions.jsonlz4"
        )
        let newest = home.appendingPathComponent(
            "Library/Application Support/zen/Profiles/current/zen-sessions.jsonlz4"
        )
        try createFixture(at: first, modifiedAt: Date(timeIntervalSince1970: 100))
        try createFixture(at: newest, modifiedAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(
            BrowserImportDataLocator.latestImportURL(
                for: .zen,
                homeDirectory: home
            )?.resolvingSymlinksInPath(),
            newest.resolvingSymlinksInPath()
        )
    }

    func testLocatorChoosesNewestChromiumSessionAcrossProfiles() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let older = home.appendingPathComponent(
            "Library/Application Support/Google/Chrome/Default/Sessions/Tabs_100"
        )
        let newest = home.appendingPathComponent(
            "Library/Application Support/Google/Chrome/Profile 1/Sessions/Session_200"
        )
        try createFixture(at: older, modifiedAt: Date(timeIntervalSince1970: 100))
        try createFixture(at: newest, modifiedAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(
            BrowserImportDataLocator.latestImportURL(
                for: .chrome,
                homeDirectory: home
            )?.resolvingSymlinksInPath(),
            newest.resolvingSymlinksInPath()
        )
    }

    func testChromeProfileDiscoveryUsesLocalStateNamesAndFindsBookmarks() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let chromeRoot = home.appendingPathComponent(
            "Library/Application Support/Google/Chrome"
        )
        let localState = chromeRoot.appendingPathComponent("Local State")
        let localStateData = try JSONSerialization.data(withJSONObject: [
            "profile": [
                "info_cache": [
                    "Default": ["name": "Personal"],
                    "Profile 1": ["name": "Work"],
                ],
            ],
        ])
        try createFixture(at: localState, data: localStateData)
        let personalBookmarks = chromeRoot.appendingPathComponent("Default/Bookmarks")
        let workBookmarks = chromeRoot.appendingPathComponent("Profile 1/Bookmarks")
        try createFixture(at: personalBookmarks)
        try createFixture(at: workBookmarks)

        let profiles = BrowserImportDataLocator.importProfiles(
            for: .chrome,
            homeDirectory: home
        )

        XCTAssertEqual(profiles.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(
            profiles.map { $0.bookmarksURL?.resolvingSymlinksInPath() },
            [personalBookmarks, workBookmarks].map { $0.resolvingSymlinksInPath() }
        )
    }

    func testPasswordStoreDiscoveryFindsArcAndChromeProfiles() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let arcRoot = home.appendingPathComponent("Library/Application Support/Arc")
        let chromeRoot = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        let arcLoginData = arcRoot.appendingPathComponent("User Data/Profile 1/Login Data")
        let chromeLoginData = chromeRoot.appendingPathComponent("Default/Login Data")
        try createFixture(at: arcLoginData)
        try createFixture(at: chromeLoginData)

        XCTAssertEqual(
            BrowserImportDataLocator.passwordStores(
                for: .arc,
                dataDirectory: arcRoot
            ).map { $0.databaseURL.resolvingSymlinksInPath() },
            [arcLoginData.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(
            BrowserImportDataLocator.passwordStores(
                for: .chrome,
                dataDirectory: chromeRoot
            ).map { $0.databaseURL.resolvingSymlinksInPath() },
            [chromeLoginData.resolvingSymlinksInPath()]
        )
    }

    func testChromiumPasswordReaderCountsAndDecryptsSupportedLogins() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let databaseURL = home.appendingPathComponent("Login Data")
        try createLoginDatabase(
            at: databaseURL,
            encryptedPassword: Data([0x76, 0x31, 0x30])
                + Data(hex: "13aaf27b4bd1b4ad2dbdea76e9ff6575")
        )
        let store = BrowserDetectedPasswordStore(
            id: "Profile 1",
            profileName: "Personal",
            databaseURL: databaseURL
        )

        let count = try await BrowserPasswordImportReader.count(in: [store])
        XCTAssertEqual(count, 1)

        let candidates = try await BrowserPasswordImportReader.candidates(
            from: [store],
            application: .arc
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].origin.description, "https://accounts.example.com")
        XCTAssertEqual(candidates[0].sourceProfileName, "Personal")

        let passwords = try await BrowserPasswordImportReader.read(
            from: [store],
            application: .arc,
            safeStorage: StubSafeStorage(secret: "test-safe-storage")
        )

        let password = try XCTUnwrap(passwords.first)
        XCTAssertEqual(passwords.count, 1)
        XCTAssertEqual(password.origin.description, "https://accounts.example.com")
        XCTAssertEqual(password.username, "paul@example.com")
        XCTAssertEqual(password.password, "hunter2")
        XCTAssertFalse(password.description.contains("hunter2"))
    }

    func testChromiumPasswordReaderPreservesStoreOrderAndV11Support() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let ciphertext = Data(hex: "13aaf27b4bd1b4ad2dbdea76e9ff6575")
        let defaultDatabaseURL = home.appendingPathComponent("Default/Login Data")
        let secondaryDatabaseURL = home.appendingPathComponent("Profile 1/Login Data")
        try createLoginDatabase(
            at: defaultDatabaseURL,
            encryptedPassword: Data("v10".utf8) + ciphertext
        )
        try createLoginDatabase(
            at: secondaryDatabaseURL,
            encryptedPassword: Data("v11".utf8) + ciphertext
        )
        let stores = [
            BrowserDetectedPasswordStore(
                id: "Default",
                profileName: "Personal",
                databaseURL: defaultDatabaseURL
            ),
            BrowserDetectedPasswordStore(
                id: "Profile 1",
                profileName: "Work",
                databaseURL: secondaryDatabaseURL
            ),
        ]

        let candidates = try await BrowserPasswordImportReader.candidates(
            from: stores,
            application: .chrome
        )
        let passwords = try await BrowserPasswordImportReader.read(
            from: stores,
            application: .chrome,
            safeStorage: StubSafeStorage(secret: "test-safe-storage")
        )

        XCTAssertEqual(candidates.map(\.sourceProfileID), ["Default", "Profile 1"])
        XCTAssertEqual(candidates.map(\.sourceProfileName), ["Personal", "Work"])
        XCTAssertEqual(passwords.map(\.sourceProfileID), ["Default", "Profile 1"])
        XCTAssertEqual(passwords.map(\.password), ["hunter2", "hunter2"])
    }

    func testDetectedSafariProfileCombinesBookmarksAndOpenTabsForReview() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bookmarksURL = home.appendingPathComponent("Bookmarks.plist")
        let sessionURL = home.appendingPathComponent("LastSession.plist")
        let bookmarks = try PropertyListSerialization.data(
            fromPropertyList: [
                "Children": [[
                    "WebBookmarkType": "WebBookmarkTypeLeaf",
                    "URLString": "https://saved.example/",
                    "URIDictionary": ["title": "Saved"],
                ]],
            ],
            format: .binary,
            options: 0
        )
        let session = try PropertyListSerialization.data(
            fromPropertyList: [
                "Windows": [[
                    "Tabs": [["URL": "https://open.example/", "Title": "Open"]],
                ]],
            ],
            format: .binary,
            options: 0
        )
        try createFixture(at: bookmarksURL, data: bookmarks)
        try createFixture(at: sessionURL, data: session)
        let payload = BrowserDetectedImportPayload(
            application: .safari,
            profiles: [BrowserDetectedImportProfile(
                id: "safari",
                name: "Safari",
                bookmarksURL: bookmarksURL,
                sessionURL: sessionURL
            )]
        )

        let imported = try await BrowserDetectedImportReader.read(payload)
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(imported.spaces.map(\.name), ["Safari"])
        XCTAssertEqual(space.savedTabs.map(\.title), ["Saved"])
        XCTAssertEqual(space.currentTabs.map(\.title), ["Open"])
    }

    func testDetectedChromeProfileKeepsBookmarksWhenItsSessionIsEncrypted() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bookmarksURL = home.appendingPathComponent("Bookmarks")
        let sessionURL = home.appendingPathComponent("Sessions/Session_100")
        let bookmarks = Data("""
        {
          "roots": {
            "bookmark_bar": {
              "type": "folder",
              "name": "Bookmarks bar",
              "children": [
                {
                  "type": "url",
                  "name": "Chromium",
                  "url": "https://www.chromium.org/"
                }
              ]
            }
          },
          "version": 1
        }
        """.utf8)
        var encryptedSession = Data("SNSS".utf8)
        encryptedSession.append(contentsOf: [5, 0, 0, 0])
        try createFixture(at: bookmarksURL, data: bookmarks)
        try createFixture(at: sessionURL, data: encryptedSession)
        let payload = BrowserDetectedImportPayload(
            application: .chrome,
            profiles: [BrowserDetectedImportProfile(
                id: "Default",
                name: "Personal",
                bookmarksURL: bookmarksURL,
                sessionURL: sessionURL
            )]
        )

        let imported = try await BrowserDetectedImportReader.read(payload)
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(imported.spaces.map(\.name), ["Personal"])
        XCTAssertEqual(space.savedTabs.map(\.title), ["Chromium"])
        XCTAssertTrue(space.currentTabs.isEmpty)
    }

    func testDetectedSafariProfileKeepsOpenTabsWhenBookmarksAreUnreadable() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bookmarksURL = home.appendingPathComponent("Bookmarks.plist")
        let sessionURL = home.appendingPathComponent("LastSession.plist")
        let session = try PropertyListSerialization.data(
            fromPropertyList: [
                "Windows": [[
                    "Tabs": [["URL": "https://open.example/", "Title": "Open"]],
                ]],
            ],
            format: .binary,
            options: 0
        )
        try createFixture(at: bookmarksURL, data: Data("not a plist".utf8))
        try createFixture(at: sessionURL, data: session)
        let payload = BrowserDetectedImportPayload(
            application: .safari,
            profiles: [BrowserDetectedImportProfile(
                id: "safari",
                name: "Safari",
                bookmarksURL: bookmarksURL,
                sessionURL: sessionURL
            )]
        )

        let imported = try await BrowserDetectedImportReader.read(payload)
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(imported.spaces.map(\.name), ["Safari"])
        XCTAssertTrue(space.savedTabs.isEmpty)
        XCTAssertEqual(space.currentTabs.map(\.title), ["Open"])
    }

    func testSafariFolderSelectionFindsBookmarksAndLastSessionTogether() throws {
        let folder = try makeTemporaryHome().appendingPathComponent("Safari")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let bookmarksURL = folder.appendingPathComponent("Bookmarks.plist")
        let sessionURL = folder.appendingPathComponent("LastSession.plist")
        try createFixture(at: bookmarksURL)
        try createFixture(at: sessionURL)

        let profile = try XCTUnwrap(
            BrowserImportDataLocator.safariProfile(in: folder)
        )

        XCTAssertEqual(profile.name, "Safari")
        XCTAssertEqual(profile.bookmarksURL, bookmarksURL)
        XCTAssertEqual(profile.sessionURL, sessionURL)
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-import-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func createFixture(
        at url: URL,
        modifiedAt: Date = Date(),
        data: Data = Data("fixture".utf8)
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: url.path
        )
    }

    private func createLoginDatabase(
        at url: URL,
        encryptedPassword: Data
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let handle = try XCTUnwrap(database)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(
            sqlite3_exec(
                handle,
                "CREATE TABLE logins (origin_url TEXT, username_value TEXT, password_value BLOB, blacklisted_by_user INTEGER);",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                handle,
                "INSERT INTO logins VALUES (?, ?, ?, 0);",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        let insert = try XCTUnwrap(statement)
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_text(insert, 1, "https://accounts.example.com/login", -1, sqliteTransient)
        sqlite3_bind_text(insert, 2, "paul@example.com", -1, sqliteTransient)
        _ = encryptedPassword.withUnsafeBytes { bytes in
            sqlite3_bind_blob(insert, 3, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        XCTAssertEqual(sqlite3_step(insert), SQLITE_DONE)
    }
}

private struct StubSafeStorage: BrowserSafeStorageSecretProviding {
    let secret: String

    func secret(for application: BrowserImportApplication) throws -> String {
        secret
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).compactMap { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)
        })
    }
}
