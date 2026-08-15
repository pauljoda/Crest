import Foundation
import XCTest
@testable import Crest

final class BrowserTabMigrationTests: XCTestCase {
    private let importedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testSafariSessionPropertyListImportsWindowsAndSanitizesTabs() throws {
        let propertyList: [String: Any] = [
            "SelectedWindowIndex": 1,
            "Windows": [
                [
                    "Title": "Research",
                    "SelectedTabIndex": 1,
                    "Tabs": [
                        [
                            "URL": "https://user:secret@example.com/one#section",
                            "Title": "One",
                        ],
                        [
                            "URL": "javascript:alert(1)",
                            "Title": "Unsupported",
                        ],
                        [
                            "URL": "https://webkit.org/",
                            "Title": "WebKit",
                        ],
                    ],
                ],
                [
                    "Title": "Second Window",
                    "SelectedTabIndex": 0,
                    "Tabs": [
                        ["URLString": "https://developer.apple.com/safari/", "TabTitle": "Safari"],
                    ],
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )

        let imported = try BrowserTabMigration.decode(
            data,
            source: .safari,
            importedAt: importedAt
        )

        XCTAssertEqual(imported.summary.spaceCount, 2)
        XCTAssertEqual(imported.summary.liveTabCount, 3)
        XCTAssertEqual(imported.spaces.map(\.name), ["Research", "Second Window"])
        XCTAssertEqual(
            imported.spaces[0].tabs.map { $0.url?.absoluteString },
            ["https://example.com/one#section", "https://webkit.org/"]
        )
        XCTAssertEqual(imported.spaces[0].selectedTabID, imported.spaces[0].tabs[1].id)
        XCTAssertTrue(imported.spaces.flatMap(\.tabs).allSatisfy { $0.placement == .current })
    }

    func testChromiumSNSSRestoresCurrentNavigationPinnedStateAndWindowOrder() throws {
        var fixture = ChromiumSessionFixture()
        fixture.appendTab(windowID: 10, tabID: 100, visualIndex: 0)
        fixture.appendNavigation(
            tabID: 100,
            index: 0,
            url: "https://user:secret@chromium.org/old",
            title: "Old"
        )
        fixture.appendNavigation(
            tabID: 100,
            index: 1,
            url: "https://chromium.org/current#anchor",
            title: "Current"
        )
        fixture.appendSelectedNavigation(tabID: 100, index: 1)
        fixture.appendPinned(tabID: 100)
        fixture.appendLastActive(tabID: 100, unixSeconds: 1_700_000_000)
        fixture.appendTab(windowID: 20, tabID: 200, visualIndex: 0)
        fixture.appendNavigation(
            tabID: 200,
            index: 0,
            url: "https://example.org/",
            title: "Other Window"
        )
        fixture.appendSelectedTab(windowID: 20, visualIndex: 0)
        fixture.appendActiveWindow(windowID: 20)
        fixture.appendMarker()

        let first = try BrowserTabMigration.decode(
            fixture.data,
            source: .chrome,
            importedAt: importedAt
        )
        let second = try BrowserTabMigration.decode(
            fixture.data,
            source: .chrome,
            importedAt: importedAt
        )

        XCTAssertEqual(first.spaces.map(\.name), [
            "Imported Chrome Window 2",
            "Imported Chrome Window 1",
        ])
        XCTAssertEqual(first.spaces[0].tabs.first?.title, "Other Window")
        XCTAssertEqual(first.spaces[1].tabs.first?.title, "Current")
        XCTAssertEqual(
            first.spaces[1].tabs.first?.url?.absoluteString,
            "https://chromium.org/current#anchor"
        )
        XCTAssertEqual(first.spaces[1].tabs.first?.placement, .pinned)
        XCTAssertEqual(
            first.spaces[1].tabs.first?.lastActivatedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertNotEqual(first.spaces[0].profile, first.spaces[1].profile)
        XCTAssertNotEqual(first.spaces[0].profile, second.spaces[0].profile)
    }

    func testFirefoxMozLZ4RestoresSelectedWindowsTabsAndPinnedState() throws {
        let json = """
        {
          "selectedWindow": 2,
          "windows": [
            {
              "title": "First",
              "selected": 2,
              "tabs": [
                {"index":1,"entries":[{"url":"https://one.example/","title":"One"}],"lastAccessed":1700000000000},
                {"index":2,"entries":[{"url":"https://old.example/","title":"Old"},{"url":"https://two.example/","title":"Two"}],"pinned":true,"lastAccessed":1700000100000}
              ]
            },
            {
              "title": "Selected",
              "selected": 1,
              "tabs": [
                {"index":1,"entries":[{"url":"https://selected.example/","title":"Selected Tab"}]}
              ]
            }
          ]
        }
        """
        let compressed = MozillaLZ4Fixture.encode(Data(json.utf8))

        let imported = try BrowserTabMigration.decode(
            compressed,
            source: .firefox,
            importedAt: importedAt
        )

        XCTAssertEqual(imported.spaces.map(\.name), ["Selected", "First"])
        XCTAssertEqual(imported.spaces[0].tabs.map(\.title), ["Selected Tab"])
        XCTAssertEqual(imported.spaces[1].tabs.map(\.title), ["One", "Two"])
        XCTAssertEqual(imported.spaces[1].selectedTabID, imported.spaces[1].tabs[1].id)
        XCTAssertEqual(imported.spaces[1].tabs[1].placement, .pinned)
    }

    func testSelectedWindowTracksSourceOrdinalWhenEarlierWindowsAreUnsupported() throws {
        let safariPropertyList: [String: Any] = [
            "SelectedWindowIndex": 2,
            "Windows": [
                "unsupported",
                [
                    "Title": "Selected Safari Window",
                    "Tabs": [["URL": "https://selected.safari.example/"]],
                ],
                [
                    "Title": "Other Safari Window",
                    "Tabs": [["URL": "https://other.safari.example/"]],
                ],
            ],
        ]
        let safariData = try PropertyListSerialization.data(
            fromPropertyList: safariPropertyList,
            format: .binary,
            options: 0
        )

        let safariImport = try BrowserTabMigration.decode(
            safariData,
            source: .safari,
            importedAt: importedAt
        )

        XCTAssertEqual(
            safariImport.spaces.map(\.name),
            ["Selected Safari Window", "Other Safari Window"]
        )

        let firefoxJSON = """
        {
          "selectedWindow": 2,
          "windows": [
            {"title":"Unsupported"},
            {"title":"Selected Firefox Window","tabs":[{"entries":[{"url":"https://selected.firefox.example/"}]}]},
            {"title":"Other Firefox Window","tabs":[{"entries":[{"url":"https://other.firefox.example/"}]}]}
          ]
        }
        """

        let firefoxImport = try BrowserTabMigration.decode(
            Data(firefoxJSON.utf8),
            source: .firefox,
            importedAt: importedAt
        )

        XCTAssertEqual(
            firefoxImport.spaces.map(\.name),
            ["Selected Firefox Window", "Other Firefox Window"]
        )
    }

    func testArcSidebarSessionImportCreatesCurrentTabsPerArcSpace() throws {
        let json = """
        {
          "sidebar": {
            "containers": [{
              "items": [
                "root", {"id":"root","childrenIds":["one","two"],"data":{"itemContainer":{}}},
                "one", {"id":"one","data":{"tab":{"savedTitle":"Arc","savedURL":"https://arc.net/"}}},
                "two", {"id":"two","data":{"tab":{"savedTitle":"WebKit","savedURL":"https://webkit.org/"}}}
              ],
              "spaces": ["space", {"id":"space","title":"Arc Work","containerIDs":["root"],"newContainerIDs":[]}]
            }]
          }
        }
        """

        let imported = try BrowserTabMigration.decode(
            Data(json.utf8),
            source: .arc,
            importedAt: importedAt
        )

        XCTAssertEqual(imported.spaces.first?.name, "Arc Work")
        XCTAssertEqual(imported.spaces.first?.tabs.map(\.title), ["Arc", "WebKit"])
        XCTAssertTrue(imported.spaces.first?.tabs.allSatisfy { $0.placement == .current } == true)
        XCTAssertTrue(imported.spaces.first?.folders.isEmpty == true)
    }

    func testArcSidebarPreservesFavoritesPinnedTodayFoldersIdentityAndPalette() throws {
        let json = """
        {
          "sidebar": {
            "containers": [{
              "items": [
                "favorite-root", {"id":"favorite-root","childrenIds":["favorite"],"data":{"itemContainer":{"containerType":{"topApps":{"_0":{"default":true}}}}}},
                "favorite", {"id":"favorite","data":{"tab":{"savedTitle":"Favorite","savedURL":"https://favorite.example/"}}},
                "today-root", {"id":"today-root","childrenIds":["today"],"data":{"itemContainer":{"containerType":{"spaceItems":{"_0":"space"}}}}},
                "today", {"id":"today","data":{"tab":{"savedTitle":"Today","savedURL":"https://today.example/"}}},
                "pinned-root", {"id":"pinned-root","childrenIds":["folder"],"data":{"itemContainer":{"containerType":{"spaceItems":{"_0":"space"}}}}},
                "folder", {"id":"folder","title":"Reading","childrenIds":["saved"],"data":{"list":{}}},
                "saved", {"id":"saved","data":{"tab":{"savedTitle":"Saved","savedURL":"https://saved.example/"}}}
              ],
              "spaces": [
                "space", {
                  "id":"space",
                  "title":"Arc Work",
                  "profile":{"default":true},
                  "containerIDs":["unpinned","today-root","pinned","pinned-root"],
                  "newContainerIDs":["unpinned","today-root","pinned","pinned-root"],
                  "customInfo":{
                    "iconType":{"emoji_v2":"🏛️"},
                    "windowTheme":{"primaryColorPalette":{"midTone":{"red":0.2,"green":0.4,"blue":0.7,"alpha":1}}}
                  }
                }
              ],
              "topAppsContainerIDs":[{"default":true},"favorite-root"]
            }]
          }
        }
        """

        let imported = try BrowserTabMigration.decode(
            Data(json.utf8),
            source: .arc,
            importedAt: importedAt
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(space.name, "Arc Work")
        XCTAssertEqual(space.symbol, BrowserTab.symbol(forEmoji: "🏛️"))
        XCTAssertEqual(space.tabs.map(\.title), ["Favorite", "Today", "Saved"])
        XCTAssertEqual(space.tabs.map(\.placement), [.pinned, .current, .saved])
        XCTAssertEqual(space.folders.map(\.title), ["Reading"])
        XCTAssertEqual(space.tabs[2].folderID, space.folders[0].id)
        let color = try XCTUnwrap(space.branding.colors.first)
        XCTAssertEqual(color.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(color.green, 0.4, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0.7, accuracy: 0.001)
    }

    func testZenSessionPreservesSpacesEssentialsPinnedOpenTabsAndFolders() throws {
        let json = """
        {
          "lastCollected": 1700000000000,
          "spaces": [{
            "uuid":"work",
            "name":"Zen Work",
            "theme":{"type":"gradient","gradientColors":["#244C78","#7A3F75"],"opacity":0.65,"texture":1}
          }],
          "folders": [{
            "id":"reading",
            "name":"Reading",
            "parentId":null,
            "workspaceId":"work"
          }],
          "groups": [],
          "splitViewData": [],
          "tabs": [
            {
              "entries":[{"url":"https://essential.example/","title":"Essential"}],
              "index":1,
              "lastAccessed":1700000100000,
              "pinned":true,
              "zenEssential":true,
              "zenWorkspace":"work"
            },
            {
              "entries":[{"url":"https://saved.example/","title":"Saved"}],
              "index":1,
              "lastAccessed":1700000200000,
              "pinned":true,
              "zenEssential":false,
              "zenWorkspace":"work",
              "groupId":"reading"
            },
            {
              "entries":[{"url":"https://open.example/","title":"Open"}],
              "index":1,
              "lastAccessed":1700000300000,
              "pinned":false,
              "zenEssential":false,
              "zenWorkspace":"work"
            }
          ]
        }
        """

        let imported = try BrowserTabMigration.decode(
            MozillaLZ4Fixture.encode(Data(json.utf8)),
            source: .zen,
            importedAt: importedAt
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(space.name, "Zen Work")
        XCTAssertEqual(space.symbol, "circle.hexagongrid.fill")
        XCTAssertEqual(space.tabs.map(\.title), ["Essential", "Saved", "Open"])
        XCTAssertEqual(space.tabs.map(\.placement), [.pinned, .saved, .current])
        XCTAssertEqual(space.folders.map(\.title), ["Reading"])
        XCTAssertEqual(space.tabs[1].folderID, space.folders[0].id)
        XCTAssertEqual(space.branding.themeMode, .gradient)
        XCTAssertEqual(space.branding.colors.count, 2)
    }

    func testPinnedOverflowBecomesSavedTabsInAnImportedFolder() throws {
        let tabs = (1...14).map { index in
            """
            {"entries":[{"url":"https://pin-\(index).example/","title":"Pin \(index)"}],"index":1,"pinned":true,"zenEssential":true,"zenWorkspace":"work"}
            """
        }.joined(separator: ",")
        let json = """
        {"spaces":[{"uuid":"work","name":"Work"}],"folders":[],"tabs":[\(tabs)]}
        """

        let imported = try BrowserTabMigration.decode(
            MozillaLZ4Fixture.encode(Data(json.utf8)),
            source: .zen,
            importedAt: importedAt
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(space.pinnedTabs.count, BrowserSpace.maximumPinnedTabs)
        XCTAssertEqual(space.savedTabs.count, 2)
        XCTAssertEqual(space.folders.map(\.title), ["Imported Pinned Tabs"])
        XCTAssertTrue(space.savedTabs.allSatisfy { $0.folderID == space.folders[0].id })
    }

    func testArcChromiumSessionUsesArcSpaceIdentity() throws {
        var fixture = ChromiumSessionFixture()
        fixture.appendTab(windowID: 10, tabID: 100, visualIndex: 0)
        fixture.appendNavigation(
            tabID: 100,
            index: 0,
            url: "https://arc.net/",
            title: "Arc Session"
        )
        fixture.appendMarker()

        let imported = try BrowserTabMigration.decode(
            fixture.data,
            source: .arc,
            importedAt: importedAt
        )

        XCTAssertEqual(imported.spaces.first?.name, "Imported Arc Tabs")
        XCTAssertEqual(imported.spaces.first?.symbol, "sidebar.left")
        XCTAssertEqual(imported.spaces.first?.tabs.first?.title, "Arc Session")
    }

    func testEveryTabSessionAdapterUsesSharedURLAndTitleSanitization() throws {
        for fixture in try sanitizationFixtures() {
            let imported = try BrowserTabMigration.decode(
                fixture.data,
                source: fixture.source,
                importedAt: importedAt
            )
            let tab = try XCTUnwrap(imported.spaces.first?.tabs.first)

            XCTAssertEqual(tab.title, "Shared Title", fixture.source.rawValue)
            XCTAssertEqual(
                tab.url?.absoluteString,
                fixture.expectedURL,
                fixture.source.rawValue
            )
            XCTAssertEqual(tab.lastActivatedAt, importedAt, fixture.source.rawValue)
        }
    }

    func testEncryptedOrTruncatedChromiumSessionsFailClosed() {
        var encrypted = Data("SNSS".utf8)
        encrypted.appendLittleEndian(UInt32(5))

        XCTAssertThrowsError(
            try BrowserTabMigration.decode(encrypted, source: .chrome)
        ) { error in
            XCTAssertEqual(
                error as? BrowserTabMigrationError,
                .encryptedChromiumSession
            )
        }

        var truncated = Data("SNSS".utf8)
        truncated.appendLittleEndian(UInt32(3))
        truncated.appendLittleEndian(UInt16(100))
        truncated.append(6)

        XCTAssertThrowsError(
            try BrowserTabMigration.decode(truncated, source: .chrome)
        ) { error in
            XCTAssertEqual(error as? BrowserTabMigrationError, .invalidContents)
        }
    }

    func testMalformedKnownChromiumCommandFailsClosed() {
        var fixture = ChromiumSessionFixture()
        fixture.appendTab(windowID: 10, tabID: 100, visualIndex: 0)
        fixture.appendNavigation(
            tabID: 100,
            index: 0,
            url: "https://chromium.org/",
            title: "Chromium"
        )
        fixture.appendMalformedPinnedCommand(tabID: 100)
        fixture.appendMarker()

        XCTAssertThrowsError(
            try BrowserTabMigration.decode(fixture.data, source: .chrome)
        ) { error in
            XCTAssertEqual(error as? BrowserTabMigrationError, .invalidContents)
        }
    }

    func testFirefoxMozLZ4RejectsDeclaredExpansionBeyondImportLimit() {
        var oversized = Data("mozLz40\0".utf8)
        oversized.appendLittleEndian(
            UInt32(BrowserTabMigration.maximumDecodedByteCount + 1)
        )
        oversized.append(0)

        XCTAssertThrowsError(
            try BrowserTabMigration.decode(oversized, source: .firefox)
        ) { error in
            XCTAssertEqual(
                error as? BrowserTabMigrationError,
                .resourceLimitExceeded
            )
        }
    }

    private func sanitizationFixtures() throws -> [(
        source: BrowserTabMigrationSource,
        data: Data,
        expectedURL: String
    )] {
        let safariData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Windows": [[
                    "Tabs": [[
                        "URL": "HTTPS://user:secret@safari.example/path#fragment",
                        "Title": "  Shared\n  Title  ",
                    ]],
                ]],
            ],
            format: .binary,
            options: 0
        )
        let firefoxData = Data("""
        {
          "windows": [{
            "tabs": [{
              "entries": [{
                "url": "HTTPS://user:secret@firefox.example/path#fragment",
                "title": "  Shared\\n  Title  "
              }]
            }]
          }]
        }
        """.utf8)
        let arcData = Data("""
        {
          "sidebar": {
            "containers": [{
              "items": [
                "root", {
                  "id": "root",
                  "childrenIds": ["tab"],
                  "data": {"itemContainer": {}}
                },
                "tab", {
                  "id": "tab",
                  "data": {"tab": {
                    "savedTitle": "  Shared\\n  Title  ",
                    "savedURL": "HTTPS://user:secret@arc.example/path#fragment"
                  }}
                }
              ],
              "spaces": [
                "space", {"id": "space", "containerIDs": ["root"]}
              ]
            }]
          }
        }
        """.utf8)
        let zenData = Data("""
        {
          "spaces": [{"uuid": "space"}],
          "folders": [],
          "tabs": [{
            "zenWorkspace": "space",
            "entries": [{
              "url": "HTTPS://user:secret@zen.example/path#fragment",
              "title": "  Shared\\n  Title  "
            }]
          }]
        }
        """.utf8)
        var chromiumFixture = ChromiumSessionFixture()
        chromiumFixture.appendTab(windowID: 1, tabID: 1, visualIndex: 0)
        chromiumFixture.appendNavigation(
            tabID: 1,
            index: 0,
            url: "HTTPS://user:secret@chromium.example/path#fragment",
            title: "  Shared\n  Title  "
        )
        chromiumFixture.appendMarker()

        return [
            (.safari, safariData, "https://safari.example/path#fragment"),
            (.chrome, chromiumFixture.data, "https://chromium.example/path#fragment"),
            (.firefox, firefoxData, "https://firefox.example/path#fragment"),
            (.arc, arcData, "https://arc.example/path#fragment"),
            (.zen, zenData, "https://zen.example/path#fragment"),
        ]
    }
}

private struct ChromiumSessionFixture {
    private(set) var data: Data

    init() {
        data = Data("SNSS".utf8)
        data.appendLittleEndian(UInt32(3))
    }

    mutating func appendTab(windowID: Int32, tabID: Int32, visualIndex: Int32) {
        appendCommand(0, integers: [windowID, tabID])
        appendCommand(2, integers: [tabID, visualIndex])
    }

    mutating func appendNavigation(
        tabID: Int32,
        index: Int32,
        url: String,
        title: String
    ) {
        var pickle = ChromiumPickleFixture()
        pickle.appendInt(tabID)
        pickle.appendInt(index)
        pickle.appendString(url)
        pickle.appendString16(title)
        pickle.appendString("")
        pickle.appendInt(0)
        appendCommand(6, payload: pickle.data)
    }

    mutating func appendSelectedNavigation(tabID: Int32, index: Int32) {
        appendCommand(7, integers: [tabID, index])
    }

    mutating func appendSelectedTab(windowID: Int32, visualIndex: Int32) {
        appendCommand(8, integers: [windowID, visualIndex])
    }

    mutating func appendPinned(tabID: Int32) {
        var payload = Data()
        payload.appendLittleEndian(tabID)
        payload.append(1)
        payload.append(contentsOf: [0, 0, 0])
        appendCommand(12, payload: payload)
    }

    mutating func appendMalformedPinnedCommand(tabID: Int32) {
        var payload = Data()
        payload.appendLittleEndian(tabID)
        appendCommand(12, payload: payload)
    }

    mutating func appendActiveWindow(windowID: Int32) {
        appendCommand(20, integers: [windowID])
    }

    mutating func appendLastActive(tabID: Int32, unixSeconds: TimeInterval) {
        var payload = Data()
        payload.appendLittleEndian(tabID)
        payload.append(contentsOf: [0, 0, 0, 0])
        let windowsMicroseconds = Int64((unixSeconds + 11_644_473_600) * 1_000_000)
        payload.appendLittleEndian(windowsMicroseconds)
        appendCommand(21, payload: payload)
    }

    mutating func appendMarker() {
        appendCommand(255, payload: Data())
    }

    private mutating func appendCommand(_ id: UInt8, integers: [Int32]) {
        var payload = Data()
        for integer in integers {
            payload.appendLittleEndian(integer)
        }
        appendCommand(id, payload: payload)
    }

    private mutating func appendCommand(_ id: UInt8, payload: Data) {
        data.appendLittleEndian(UInt16(payload.count + 1))
        data.append(id)
        data.append(payload)
    }
}

private struct ChromiumPickleFixture {
    private var payload = Data()

    var data: Data {
        var result = Data()
        result.appendLittleEndian(UInt32(payload.count))
        result.append(payload)
        return result
    }

    mutating func appendInt(_ value: Int32) {
        payload.appendLittleEndian(value)
    }

    mutating func appendString(_ value: String) {
        let bytes = Data(value.utf8)
        payload.appendLittleEndian(Int32(bytes.count))
        payload.append(bytes)
        alignPayload()
    }

    mutating func appendString16(_ value: String) {
        let units = Array(value.utf16)
        payload.appendLittleEndian(Int32(units.count))
        for unit in units {
            payload.appendLittleEndian(unit)
        }
        alignPayload()
    }

    private mutating func alignPayload() {
        while payload.count.isMultiple(of: 4) == false {
            payload.append(0)
        }
    }
}

private enum MozillaLZ4Fixture {
    static func encode(_ source: Data) -> Data {
        var result = Data("mozLz40\0".utf8)
        result.appendLittleEndian(UInt32(source.count))
        result.append(0xF0)
        var remainingLength = source.count - 15
        while remainingLength >= 255 {
            result.append(255)
            remainingLength -= 255
        }
        result.append(UInt8(remainingLength))
        result.append(source)
        return result
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
