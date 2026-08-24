import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserPortableArchiveTests: XCTestCase {
    func testCanonicalExportFilenameCarriesTheImportableJSONExtension() {
        XCTAssertTrue(BrowserPortableArchive.defaultFilename.hasSuffix(".json"))
    }

    func testRoundTripPreservesPortableStateWithFreshIsolationIdentities() throws {
        let source = try makePortableFixture()
        let sourceSpace = try XCTUnwrap(source.selectedSpace)

        let data = try BrowserPortableArchive.encode(
            session: source,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let imported = try BrowserPortableArchive.decode(data).materialize()
        let space = try XCTUnwrap(imported.spaces.first)

        XCTAssertEqual(imported.summary.spaceCount, 1)
        XCTAssertEqual(imported.summary.folderCount, 2)
        XCTAssertEqual(imported.summary.liveTabCount, 3)
        XCTAssertEqual(imported.summary.archivedTabCount, 1)
        XCTAssertEqual(imported.summary.historyEntryCount, 1)

        XCTAssertNotEqual(space.id, sourceSpace.id)
        XCTAssertNotEqual(space.profile, sourceSpace.profile)
        XCTAssertEqual(space.name, sourceSpace.name)
        XCTAssertEqual(space.symbol, sourceSpace.symbol)
        XCTAssertEqual(space.accent, sourceSpace.accent)
        XCTAssertEqual(space.branding, sourceSpace.branding)
        XCTAssertEqual(space.browsingPreferences, sourceSpace.browsingPreferences)
        XCTAssertEqual(space.credentialPreferences, .default)

        XCTAssertEqual(space.folders.map(\.title), sourceSpace.folders.map(\.title))
        XCTAssertEqual(space.folders.map(\.color), sourceSpace.folders.map(\.color))
        XCTAssertEqual(
            space.folders.map(\.isCollapsed),
            sourceSpace.folders.map(\.isCollapsed)
        )
        XCTAssertNotEqual(space.folders.map(\.id), sourceSpace.folders.map(\.id))
        XCTAssertNil(space.folders[0].parentID)
        XCTAssertEqual(space.folders[1].parentID, space.folders[0].id)
        XCTAssertTrue(space.folderTree.isValid)
        XCTAssertTrue(Set(space.tabs.map(\.id)).isDisjoint(with: sourceSpace.tabs.map(\.id)))
        XCTAssertEqual(space.tabs.map(\.placement), sourceSpace.tabs.map(\.placement))
        XCTAssertTrue(space.tabs.allSatisfy { $0.faviconData == nil })

        let selectedTab = try XCTUnwrap(
            space.tabs.first { $0.id == space.selectedTabID }
        )
        XCTAssertEqual(selectedTab.title, "Reference")
        XCTAssertEqual(
            space.savedTabs.first?.folderID,
            space.folders.last?.id
        )
        XCTAssertEqual(
            space.pinnedTabs.first?.url?.absoluteString,
            "https://example.com/private#section"
        )
        XCTAssertEqual(
            space.history.first?.url.absoluteString,
            "https://example.com/history"
        )
    }

    func testEncodedArchiveCannotContainCredentialOrWebsiteRuntimeState() throws {
        let data = try BrowserPortableArchive.encode(session: try makePortableFixture())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("credentialPreferences"))
        XCTAssertFalse(json.contains("faviconData"))
        XCTAssertFalse(json.contains("\"profile\""))
        XCTAssertFalse(json.contains("extension"))
        XCTAssertFalse(json.contains("permission"))
        XCTAssertFalse(json.contains("destinationURL"))
        XCTAssertFalse(json.contains("riskAssessment"))
        XCTAssertTrue(json.contains(BrowserPortableArchive.formatIdentifier))
    }

    func testVersionThreeArchiveKeepsItsCanonicalJSONKeys() throws {
        let data = try BrowserPortableArchive.encode(
            session: try makePortableFixture(),
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        let space = try XCTUnwrap(spaces.first)
        let folders = try XCTUnwrap(space["folders"] as? [[String: Any]])
        let tabs = try XCTUnwrap(space["tabs"] as? [[String: Any]])
        let archivedTabs = try XCTUnwrap(space["archivedTabs"] as? [[String: Any]])
        let history = try XCTUnwrap(space["history"] as? [[String: Any]])

        XCTAssertEqual(root["schemaVersion"] as? Int, 3)
        XCTAssertEqual(
            Set(root.keys),
            Set(["exportedAt", "format", "schemaVersion", "spaces"])
        )
        XCTAssertEqual(
            Set(space.keys),
            Set([
                "accent", "archivedTabs", "branding", "browsingPreferences",
                "folders", "history", "name", "selectedTabID", "symbol", "tabs",
                "splitGroups",
            ])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(folders.first).keys),
            Set(["color", "id", "isCollapsed", "symbol", "title"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(folders.last).keys),
            Set(["color", "id", "isCollapsed", "parentID", "symbol", "title"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(tabs.first).keys),
            Set([
                "id", "lastActivatedAt", "placement", "savedURL", "symbol",
                "title", "url",
            ])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(archivedTabs.first).keys),
            Set(["archivedAt", "reason", "tab"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(history.first).keys),
            Set([
                "firstVisitedAt", "lastVisitedAt", "title", "url", "visitCount",
            ])
        )
    }

    func testSplitGroupMembershipAndCustomizationRoundTripWithFreshIdentity()
        throws
    {
        let sourceGroupID = SplitGroupID()
        let emoji = "👨🏽‍💻"
        let tint = BrowserSpaceBrandColor(red: 0.22, green: 0.54, blue: 0.76)
        let first = BrowserTab(
            title: "First",
            url: URL(string: "https://example.com/first"),
            placement: .current,
            splitGroupID: sourceGroupID
        )
        let second = BrowserTab(
            title: "Second",
            url: URL(string: "https://example.com/second"),
            placement: .current,
            splitGroupID: sourceGroupID
        )
        let metadata = BrowserSplitGroupMetadata(
            id: sourceGroupID,
            customTitle: "Portable Pair",
            titleModifiedAt: Date(timeIntervalSince1970: 100),
            customIconSymbol: BrowserIconSymbol.symbol(forEmoji: emoji),
            iconModifiedAt: Date(timeIntervalSince1970: 200),
            tint: tint,
            tintModifiedAt: Date(timeIntervalSince1970: 300)
        )
        let sourceSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Split",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            folders: [],
            tabs: [first, second],
            splitGroups: [metadata],
            selectedTabID: first.id
        )
        let source = BrowserSession(
            spaces: [sourceSpace],
            selectedSpaceID: sourceSpace.id
        )

        let imported = try BrowserPortableArchive.decode(
            BrowserPortableArchive.encode(session: source)
        ).materialize()
        let importedSpace = try XCTUnwrap(imported.spaces.first)
        let importedGroupID = try XCTUnwrap(
            importedSpace.tabs.first?.splitGroupID
        )

        XCTAssertNotEqual(importedGroupID, sourceGroupID)
        XCTAssertEqual(
            importedSpace.tabs.map(\.splitGroupID),
            [importedGroupID, importedGroupID]
        )
        let importedMetadata = try XCTUnwrap(
            importedSpace.splitGroupMetadata(for: importedGroupID)
        )
        XCTAssertEqual(importedMetadata.displayTitle, "Portable Pair")
        XCTAssertEqual(importedMetadata.emojiIcon, emoji)
        XCTAssertEqual(importedMetadata.tint, tint)
    }

    func testVersionTwoArchiveWithoutSplitFieldsStillImports() throws {
        let data = try BrowserPortableArchive.encode(session: try makePortableFixture())
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        root["schemaVersion"] = 2
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        for index in spaces.indices {
            spaces[index].removeValue(forKey: "splitGroups")
            var tabs = try XCTUnwrap(spaces[index]["tabs"] as? [[String: Any]])
            for tabIndex in tabs.indices {
                tabs[tabIndex].removeValue(forKey: "splitGroupID")
            }
            spaces[index]["tabs"] = tabs
        }
        root["spaces"] = spaces

        let imported = try BrowserPortableArchive.decode(
            JSONSerialization.data(withJSONObject: root)
        ).materialize()

        XCTAssertEqual(imported.spaces.count, 1)
        XCTAssertTrue(imported.spaces[0].splitGroups.isEmpty)
        XCTAssertTrue(
            imported.spaces[0].tabs.allSatisfy { $0.splitGroupID == nil }
        )
    }

    func testImportAppendsSpacesSelectsFirstImportAndPersists() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let originalIDs = Set(store.session.spaces.map(\.id))
        let imported = try BrowserPortableArchive(
            session: try makePortableFixture()
        ).materialize()

        try store.importPortableArchive(imported)

        XCTAssertEqual(
            store.session.spaces.count,
            BrowserSession.preview.spaces.count + imported.spaces.count
        )
        XCTAssertTrue(originalIDs.isSubset(of: store.session.spaces.map(\.id)))
        XCTAssertEqual(store.session.selectedSpaceID, imported.spaces[0].id)
        XCTAssertEqual(persistence.session, store.session)
    }

    func testUnsupportedSchemaVersionIsRejectedBeforeMaterialization() throws {
        let data = try BrowserPortableArchive.encode(session: try makePortableFixture())
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        root["schemaVersion"] = BrowserPortableArchive.currentSchemaVersion + 1
        let futureData = try JSONSerialization.data(withJSONObject: root)

        let archive = try BrowserPortableArchive.decode(futureData)

        XCTAssertThrowsError(try archive.materialize()) { error in
            XCTAssertEqual(
                error as? BrowserPortableArchiveError,
                .unsupportedSchemaVersion(
                    BrowserPortableArchive.currentSchemaVersion + 1
                )
            )
        }
    }

    func testLegacyVersionOneArchiveImportsFoldersAtTopLevel() throws {
        let data = try BrowserPortableArchive.encode(session: try makePortableFixture())
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        root["schemaVersion"] = 1
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        var folders = try XCTUnwrap(spaces[0]["folders"] as? [[String: Any]])
        for index in folders.indices {
            folders[index].removeValue(forKey: "parentID")
            folders[index].removeValue(forKey: "isCollapsed")
        }
        spaces[0]["folders"] = folders
        root["spaces"] = spaces

        let imported = try BrowserPortableArchive.decode(
            JSONSerialization.data(withJSONObject: root)
        ).materialize()

        XCTAssertEqual(imported.spaces[0].folders.count, 2)
        XCTAssertTrue(imported.spaces[0].folders.allSatisfy { $0.parentID == nil })
        XCTAssertTrue(imported.spaces[0].folders.allSatisfy { !$0.isCollapsed })
    }

    func testCyclicFolderHierarchyIsRejected() throws {
        let data = try BrowserPortableArchive.encode(session: try makePortableFixture())
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        var folders = try XCTUnwrap(spaces[0]["folders"] as? [[String: Any]])
        let firstID = try XCTUnwrap(folders[0]["id"] as? String)
        let secondID = try XCTUnwrap(folders[1]["id"] as? String)
        folders[0]["parentID"] = secondID
        folders[1]["parentID"] = firstID
        spaces[0]["folders"] = folders
        root["spaces"] = spaces

        XCTAssertThrowsError(
            try BrowserPortableArchive.decode(
                JSONSerialization.data(withJSONObject: root)
            ).materialize()
        ) { error in
            XCTAssertEqual(error as? BrowserPortableArchiveError, .invalidContents)
        }
    }

    func testImportCannotGrowTheSessionPastTheSpaceLimit() throws {
        var existingSpaces: [BrowserSpace] = []
        for _ in 0..<(BrowserPortableArchive.maximumSpaceCount / 2) {
            existingSpaces.append(
                contentsOf: try BrowserPortableArchive(
                    session: .preview
                ).materialize().spaces
            )
        }
        let fullSession = BrowserSession(
            spaces: existingSpaces,
            selectedSpaceID: existingSpaces[0].id
        )
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: fullSession, persistence: persistence)
        let imported = try BrowserPortableArchive(
            session: try makePortableFixture()
        ).materialize()

        XCTAssertThrowsError(try store.importPortableArchive(imported)) {
            XCTAssertEqual(
                $0 as? BrowserPortableArchiveError,
                .spaceLimitExceeded(BrowserPortableArchive.maximumSpaceCount)
            )
        }
        XCTAssertEqual(store.session, fullSession)
        XCTAssertNil(persistence.session)
    }

    func testSavedTabWithUnknownFolderIsRejected() throws {
        let data = try BrowserPortableArchive.encode(session: try makePortableFixture())
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        var tabs = try XCTUnwrap(spaces[0]["tabs"] as? [[String: Any]])
        let savedIndex = try XCTUnwrap(
            tabs.firstIndex {
                $0["placement"] as? String == TabPlacement.saved.rawValue
            })
        tabs[savedIndex]["folderID"] = UUID().uuidString
        spaces[0]["tabs"] = tabs
        root["spaces"] = spaces
        let malformedData = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(
            try BrowserPortableArchive.decode(malformedData).materialize()
        ) { error in
            XCTAssertEqual(
                error as? BrowserPortableArchiveError,
                .invalidContents
            )
        }
    }

    func testDuplicateHistoryURLsMergeWithoutDuplicatingRows() throws {
        let source = try makePortableFixture()
        let sourceEntry = try XCTUnwrap(source.selectedSpace?.history.first)
        let data = try BrowserPortableArchive.encode(session: source)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        var history = try XCTUnwrap(spaces[0]["history"] as? [[String: Any]])
        var duplicate = try XCTUnwrap(history.first)
        duplicate["title"] = "Newer title"
        duplicate["firstVisitedAt"] =
            sourceEntry.firstVisitedAt
            .addingTimeInterval(100)
            .timeIntervalSince1970 * 1_000
        duplicate["lastVisitedAt"] =
            sourceEntry.lastVisitedAt
            .addingTimeInterval(100)
            .timeIntervalSince1970 * 1_000
        duplicate["visitCount"] = 2
        history.append(duplicate)
        spaces[0]["history"] = history
        root["spaces"] = spaces
        let duplicateData = try JSONSerialization.data(withJSONObject: root)

        let imported = try BrowserPortableArchive.decode(
            duplicateData
        ).materialize()
        let importedHistory = try XCTUnwrap(imported.spaces.first?.history)

        XCTAssertEqual(importedHistory.count, 1)
        XCTAssertEqual(importedHistory[0].visitCount, sourceEntry.visitCount + 2)
        XCTAssertEqual(importedHistory[0].title, "Newer title")
    }

    private func makePortableFixture() throws -> BrowserSession {
        let folder = SavedFolder(
            title: "Research",
            symbol: "folder.fill",
            color: BrowserSpaceBrandColor(red: 0.18, green: 0.42, blue: 0.72)
        )
        let nestedFolder = SavedFolder(
            title: "WebKit",
            symbol: "folder.fill",
            parentID: folder.id,
            isCollapsed: true
        )
        let pinned = BrowserTab(
            title: "Private URL",
            url: URL(string: "https://user:secret@example.com/private#section"),
            symbol: "globe",
            faviconData: Data([0x01, 0x02, 0x03]),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let saved = BrowserTab(
            title: "Reference",
            url: URL(string: "https://developer.apple.com/documentation/webkit"),
            symbol: "book.closed",
            faviconData: Data([0x04]),
            placement: .saved,
            folderID: nestedFolder.id,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let startPage = BrowserTab.startPage(
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let archived = ArchivedTab(
            tab: BrowserTab(
                title: "Closed",
                url: URL(string: "https://example.net/closed"),
                placement: .current,
                lastActivatedAt: Date(timeIntervalSince1970: 1_699_000_000)
            ),
            archivedAt: Date(timeIntervalSince1970: 1_699_000_100),
            reason: .closed
        )
        let history = BrowserHistoryEntry(
            url: URL(string: "https://user:secret@example.com/history#fragment")!,
            title: "History",
            firstVisitedAt: Date(timeIntervalSince1970: 1_600_000_000),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
            visitCount: 4
        )
        var browsingPreferences = BrowserSpaceBrowsingPreferences(
            searchProvider: .brave,
            currentTabCleanupPolicy: .after30Days,
            dataRetention: BrowserSpaceDataRetentionPreferences(
                history: .ninetyDays,
                archive: .thirtyDays,
                downloads: .oneWeek
            )
        )
        let kagi = try BrowserCustomSearchProvider(
            id: UUID(
                uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x02, 0x64)
            ),
            name: "Kagi",
            searchURLTemplate: "https://kagi.com/search?q=%s",
            suggestionURLTemplate: "https://kagi.com/api/autosuggest?q=%s"
        )
        try browsingPreferences.upsertCustomSearchProvider(kagi)
        browsingPreferences.searchProvider = kagi.provider
        browsingPreferences.searchSuggestionsEnabled = true
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Portable Work",
            symbol: "briefcase.fill",
            accent: .teal,
            folders: [folder, nestedFolder],
            tabs: [pinned, saved, startPage],
            archivedTabs: [archived],
            history: [history],
            browsingPreferences: browsingPreferences,
            credentialPreferences: BrowserCredentialPreferences(
                syncsCrestPasswordsWithICloud: false,
                alsoOffersSaveToSystemPasswords: true
            ),
            selectedTabID: saved.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }
}
