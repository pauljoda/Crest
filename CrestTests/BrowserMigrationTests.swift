import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Crest

@MainActor
final class BrowserMigrationTests: XCTestCase {
    func testChromeBookmarkPickerAcceptsTheExtensionlessProfileFile() {
        let allowedTypes = BrowserBookmarkMigrationSource.chromeBookmarks
            .allowedContentTypes

        XCTAssertTrue(allowedTypes.contains(.json))
        XCTAssertTrue(
            allowedTypes.contains(.data),
            "Chrome stores bookmarks in an extensionless file named Bookmarks."
        )
    }

    func testNetscapeHTMLImportPreservesNestedFoldersAndSanitizesURLs() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
          <DT><H3 ADD_DATE="1700000000">Research &amp; Notes</H3>
          <DL><p>
            <DT><A HREF="https://user:secret@example.com/path?a=1&amp;b=2" ADD_DATE="1700000100">One &lt;Two&gt;</A>
            <DT><A HREF="javascript:alert(1)">Unsupported</A>
            <DT><H3>Nested</H3>
            <DL><p><DT><A HREF='https://swift.org/'>Swift</A></DL><p>
          </DL><p>
        </DL><p>
        """

        let firstImport = try BrowserBookmarkMigration.decode(
            Data(html.utf8),
            source: .htmlBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let secondImport = try BrowserBookmarkMigration.decode(
            Data(html.utf8),
            source: .htmlBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let space = try XCTUnwrap(firstImport.spaces.first)

        XCTAssertEqual(firstImport.summary.spaceCount, 1)
        XCTAssertEqual(firstImport.summary.folderCount, 2)
        XCTAssertEqual(firstImport.summary.liveTabCount, 2)
        XCTAssertEqual(space.name, "Imported Bookmarks")
        XCTAssertEqual(space.folders.map(\.title), ["Research & Notes", "Nested"])
        XCTAssertEqual(space.folders[1].parentID, space.folders[0].id)
        XCTAssertTrue(space.tabs.allSatisfy { $0.placement == .saved })
        XCTAssertEqual(
            space.tabs.map { $0.url?.absoluteString },
            ["https://example.com/path?a=1&b=2", "https://swift.org/"]
        )
        XCTAssertEqual(space.tabs[0].folderID, space.folders[0].id)
        XCTAssertEqual(space.tabs[1].folderID, space.folders[1].id)
        XCTAssertEqual(space.tabs[0].title, "One <Two>")
        XCTAssertTrue(
            Set(space.tabs.map(\.id)).isDisjoint(
                with: secondImport.spaces[0].tabs.map(\.id)
            )
        )
        XCTAssertNotEqual(space.profile, secondImport.spaces[0].profile)
    }

    func testHTMLExportUsesTheStandardFormatAndExcludesCurrentTabs() throws {
        let source = makeExportFixture()

        let data = try BrowserBookmarkMigration.encodeHTML(
            session: source,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        let imported = try BrowserBookmarkMigration.decode(
            data,
            source: .htmlBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let tabs = try XCTUnwrap(imported.spaces.first?.tabs)

        XCTAssertTrue(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        XCTAssertTrue(html.contains("Crest Bookmarks"))
        XCTAssertTrue(html.contains("A &lt; B &amp; &quot;C&quot;"))
        XCTAssertFalse(html.contains("user:secret"))
        XCTAssertFalse(html.contains("current.example"))
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(
            Set(tabs.compactMap { $0.url?.host }),
            Set(["example.com", "example.org"])
        )
    }

    func testSafariPropertyListImportPreservesBookmarkFolders() throws {
        let propertyList: [String: Any] = [
            "Title": "Root",
            "WebBookmarkFileVersion": 1,
            "Children": [
                [
                    "Title": "Favorites",
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "URLString": "https://developer.apple.com/safari/",
                            "URIDictionary": ["title": "Safari"],
                        ],
                    ],
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )

        let imported = try BrowserBookmarkMigration.decode(
            data,
            source: .safariBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(space.name, "Imported from Safari")
        XCTAssertEqual(space.folders.map(\.title), ["Favorites"])
        XCTAssertEqual(space.tabs.map(\.title), ["Safari"])
        XCTAssertEqual(space.tabs.first?.folderID, space.folders.first?.id)
    }

    func testChromeBookmarksJSONImportsEveryRoot() throws {
        let json = """
        {
          "checksum": "ignored",
          "roots": {
            "bookmark_bar": {
              "type": "folder",
              "name": "Bookmarks bar",
              "children": [
                {"type":"url","name":"Chromium","url":"https://www.chromium.org/","date_added":"13370000000000000"}
              ]
            },
            "other": {
              "type": "folder",
              "name": "Other bookmarks",
              "children": [
                {"type":"folder","name":"Reference","children":[
                  {"type":"url","name":"WebKit","url":"https://webkit.org/"}
                ]}
              ]
            }
          },
          "version": 1
        }
        """

        let imported = try BrowserBookmarkMigration.decode(
            Data(json.utf8),
            source: .chromeBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(space.name, "Imported from Chrome")
        XCTAssertEqual(
            space.folders.map(\.title),
            ["Bookmarks bar", "Other bookmarks", "Reference"]
        )
        XCTAssertEqual(space.tabs.map(\.title), ["Chromium", "WebKit"])
        XCTAssertTrue(space.folderTree.isValid)
    }

    func testFirefoxJSONImportUnderstandsPlacesBackupShape() throws {
        let json = """
        {
          "title": "",
          "type": "text/x-moz-place-container",
          "children": [
            {
              "title": "Bookmarks Menu",
              "type": "text/x-moz-place-container",
              "children": [
                {
                  "title": "Mozilla",
                  "uri": "https://www.mozilla.org/",
                  "type": "text/x-moz-place",
                  "dateAdded": 1700000000000000
                }
              ]
            }
          ]
        }
        """

        let imported = try BrowserBookmarkMigration.decode(
            Data(json.utf8),
            source: .firefoxBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(space.name, "Imported from Firefox")
        XCTAssertEqual(space.folders.map(\.title), ["Bookmarks Menu"])
        XCTAssertEqual(space.tabs.map(\.title), ["Mozilla"])
    }

    func testArcSidebarImportPreservesArcSpacesFoldersAndTabs() throws {
        let json = """
        {
          "sidebar": {
            "containers": [
              {
                "items": [
                  "root",
                  {"id":"root","title":"","childrenIds":["tab-one","folder"],"data":{"itemContainer":{"containerType":{"spaceItems":[null]}}}},
                  "folder",
                  {"id":"folder","title":"Docs","parentID":"root","childrenIds":["tab-two"],"data":{"list":{}}},
                  "tab-one",
                  {"id":"tab-one","title":"","parentID":"root","data":{"tab":{"savedTitle":"Arc","savedURL":"https://arc.net/","timeLastActiveAt":1700000000}}},
                  "tab-two",
                  {"id":"tab-two","title":"","parentID":"folder","data":{"tab":{"savedTitle":"WebKit","savedURL":"https://webkit.org/","timeLastActiveAt":1700000100}}}
                ],
                "spaces": [
                  "space-one",
                  {"id":"space-one","title":"Work","containerIDs":["root"],"newContainerIDs":[]}
                ],
                "topAppsContainerIDs": []
              }
            ]
          }
        }
        """

        let imported = try BrowserBookmarkMigration.decode(
            Data(json.utf8),
            source: .arcSidebar,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(imported.summary.spaceCount, 1)
        XCTAssertEqual(space.name, "Work")
        XCTAssertEqual(space.folders.map(\.title), ["Docs"])
        XCTAssertEqual(space.tabs.map(\.title), ["Arc", "WebKit"])
        XCTAssertNil(space.tabs[0].folderID)
        XCTAssertEqual(space.tabs[1].folderID, space.folders[0].id)
    }

    func testBrowserWithoutAnExposedThemeUsesNeutralImportBranding() throws {
        let json = """
        {
          "sidebar": {
            "containers": [
              {
                "items": [
                  "root",
                  {"id":"root","title":"","childrenIds":["tab-one"],"data":{"itemContainer":{"containerType":{"spaceItems":[null]}}}},
                  "tab-one",
                  {"id":"tab-one","title":"","parentID":"root","data":{"tab":{"savedTitle":"Arc","savedURL":"https://arc.net/","timeLastActiveAt":1700000000}}}
                ],
                "spaces": [
                  "space-one",
                  {"id":"space-one","title":"Work","containerIDs":["root"],"newContainerIDs":[]}
                ],
                "topAppsContainerIDs": []
              }
            ]
          }
        }
        """

        let imported = try BrowserTabMigration.decode(
            Data(json.utf8),
            source: .arc,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let branding = try XCTUnwrap(imported.spaces.first?.branding)

        XCTAssertEqual(branding, .neutralImport(symbol: "sidebar.left"))
        XCTAssertEqual(branding.colors.count, 1)
        XCTAssertEqual(branding.bannerPattern, .solid)
        XCTAssertFalse(branding.showsTexture)
    }

    func testImportRejectsASeventeenthNestedFolderBeforeCreatingASpace() {
        let nestedFolders = (0..<17).map { index in
            "<DT><H3>Level \(index)</H3><DL><p>"
        }.joined()
        let closingFolders = String(repeating: "</DL><p>", count: 17)
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>\(nestedFolders)<DT><A HREF="https://example.com/">Example</A>\(closingFolders)</DL><p>
        """

        XCTAssertThrowsError(
            try BrowserBookmarkMigration.decode(
                Data(html.utf8),
                source: .htmlBookmarks,
                importedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserBookmarkMigrationError,
                .resourceLimitExceeded
            )
        }
    }

    func testStoreImportAppendsFreshMigrationSpaceAndPersists() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p><DT><A HREF="https://example.com/">Example</A></DL><p>
        """
        let imported = try BrowserBookmarkMigration.decode(
            Data(html.utf8),
            source: .htmlBookmarks,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try store.importPortableArchive(imported)

        XCTAssertEqual(store.session.selectedSpace?.name, "Imported Bookmarks")
        XCTAssertEqual(store.selectedTab?.title, "Example")
        XCTAssertEqual(persistence.session, store.session)
    }

    private func makeExportFixture() -> BrowserSession {
        let folder = SavedFolder(title: "Research", symbol: "folder")
        let pinned = BrowserTab(
            title: "Pinned",
            url: URL(string: "https://user:secret@example.com/pinned"),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let saved = BrowserTab(
            title: "A < B & \"C\"",
            url: URL(string: "https://example.org/?a=1&b=2"),
            placement: .saved,
            folderID: folder.id,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let current = BrowserTab(
            title: "Current",
            url: URL(string: "https://current.example/"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase",
            accent: .indigo,
            folders: [folder],
            tabs: [pinned, saved, current],
            selectedTabID: current.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }
}
