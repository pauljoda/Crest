import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserDataPortabilityModelTests: XCTestCase {
    func testLockedSpacesPreventBothSensitiveExports() {
        let context = makeContext(isProtected: true)

        context.model.prepareExport()
        context.model.prepareBookmarkExport()

        XCTAssertEqual(context.operations.portableDocumentRequestCount, 0)
        XCTAssertEqual(context.operations.bookmarkDocumentRequestCount, 0)
        XCTAssertFalse(context.model.isPreparingExport)
        XCTAssertFalse(context.model.isPreparingBookmarkExport)
    }

    func testRelockingDuringPreparationDiscardsThePreparedDocument() async {
        let operations = TestOperations(suspendsPortableExport: true)
        let context = makeContext(isProtected: true, operations: operations)
        let didUnlock = await context.spaceAccess.unlock(context.space)
        XCTAssertTrue(didUnlock)

        context.model.prepareExport()
        await waitUntil { operations.portableDocumentRequestCount == 1 }
        context.spaceAccess.lock(context.space.id)
        operations.finishPortableExportPreparation()
        await waitUntil { !context.model.isPreparingExport }

        XCTAssertNil(context.model.exportDocument)
        XCTAssertFalse(context.model.isExporting)
    }

    func testExporterCompletionClearsItsPreparedDocument() async {
        let context = makeContext()

        context.model.prepareExport()
        await waitUntil { context.model.isExporting }
        XCTAssertNotNil(context.model.exportDocument)

        context.model.finishPortableExport(
            .success(URL(fileURLWithPath: "/preview/crest-browser-data.json"))
        )

        XCTAssertNil(context.model.exportDocument)
        XCTAssertNotNil(context.model.status)
    }

    func testBookmarkSourceSelectionStaysPairedWithItsImporter() async {
        let context = makeContext()
        context.operations.importToReturn = makeImport()

        context.model.beginBookmarkImport(from: .firefoxBookmarks)
        context.model.finishBookmarkImport(
            .success([URL(fileURLWithPath: "/preview/bookmarks.html")])
        )
        await waitUntil { context.operations.bookmarkImportRequestCount == 1 }

        XCTAssertEqual(
            context.operations.lastBookmarkSource,
            .firefoxBookmarks
        )
    }

    func testImportPreservesEveryExistingSpaceAndProfileIdentity() async throws {
        let context = makeContext()
        let existingAssignments = Dictionary(
            uniqueKeysWithValues: context.browser.session.spaces.map {
                ($0.id, $0.profile.id)
            }
        )
        let imported = makeImport()
        context.operations.importToReturn = imported

        context.model.beginPortableImport()
        context.model.finishPortableImport(
            .success([URL(fileURLWithPath: "/preview/crest-browser-data.json")])
        )
        await waitUntil { context.operations.portableImportRequestCount == 1 }

        for (spaceID, profileID) in existingAssignments {
            XCTAssertEqual(
                context.browser.session.space(id: spaceID)?.profile.id,
                profileID
            )
        }
        let importedSpace = try XCTUnwrap(imported.spaces.first)
        XCTAssertEqual(
            context.browser.session.space(id: importedSpace.id)?
                .profile.id,
            importedSpace.profile.id
        )
        XCTAssertFalse(existingAssignments.keys.contains(importedSpace.id))
        XCTAssertFalse(existingAssignments.values.contains(importedSpace.profile.id))
    }

    private func makeContext(
        isProtected: Bool = false,
        operations: TestOperations = TestOperations()
    ) -> Context {
        let space = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(1)),
            profile: BrowsingProfile(id: Self.uuid(2)),
            name: "Existing",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open,
            selectedTabID: nil
        )
        let session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        let browser = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: TestAuthenticator()
        )
        return Context(
            space: space,
            browser: browser,
            spaceAccess: spaceAccess,
            operations: operations,
            model: BrowserDataPortabilityModel(
                browser: browser,
                spaceAccess: spaceAccess,
                operations: operations
            )
        )
    }

    private func makeImport() -> BrowserPortableImport {
        let importedSpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(11)),
            profile: BrowsingProfile(id: Self.uuid(12)),
            name: "Imported",
            symbol: "shippingbox.fill",
            accent: .orange,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        return BrowserPortableImport(
            spaces: [importedSpace],
            summary: BrowserPortableImportSummary(
                spaceCount: 1,
                folderCount: 0,
                liveTabCount: 0,
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x44, 0x41, 0x54, 0x41, 0x50, 0x4F, 0x52, 0x54,
                0x54, 0x45, 0x53, 0x54, 0x00, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let space: BrowserSpace
        let browser: BrowserStore
        let spaceAccess: BrowserSpaceAccessController
        let operations: TestOperations
        let model: BrowserDataPortabilityModel
    }

    private final class TestAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }

    private final class TestOperations: BrowserDataPortabilityOperating {
        private let suspendsPortableExport: Bool
        private var portableExportContinuation: CheckedContinuation<BrowserPortableArchiveDocument, Error>?

        var portableDocumentRequestCount = 0
        var bookmarkDocumentRequestCount = 0
        var portableImportRequestCount = 0
        var bookmarkImportRequestCount = 0
        var lastBookmarkSource: BrowserBookmarkMigrationSource?
        var importToReturn = BrowserPortableImport(
            spaces: [],
            summary: BrowserPortableImportSummary(
                spaceCount: 0,
                folderCount: 0,
                liveTabCount: 0,
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        )

        init(suspendsPortableExport: Bool = false) {
            self.suspendsPortableExport = suspendsPortableExport
        }

        func portableArchiveDocument(
            for _: BrowserSession
        ) async throws -> BrowserPortableArchiveDocument {
            portableDocumentRequestCount += 1
            if suspendsPortableExport {
                return try await withCheckedThrowingContinuation {
                    portableExportContinuation = $0
                }
            }
            return BrowserPortableArchiveDocument(data: Data([0x7B, 0x7D]))
        }

        func portableImport(from _: URL) async throws -> BrowserPortableImport {
            portableImportRequestCount += 1
            return importToReturn
        }

        func bookmarkDocument(
            for _: BrowserSession
        ) async throws -> BrowserBookmarkHTMLDocument {
            bookmarkDocumentRequestCount += 1
            return BrowserBookmarkHTMLDocument(data: Data("<DL></DL>".utf8))
        }

        func bookmarkImport(
            from _: URL,
            source: BrowserBookmarkMigrationSource
        ) async throws -> BrowserPortableImport {
            bookmarkImportRequestCount += 1
            lastBookmarkSource = source
            return importToReturn
        }

        func historyImport(
            from _: URL,
            source _: BrowserHistoryMigrationSource
        ) async throws -> BrowserPortableImport {
            importToReturn
        }

        func tabImport(
            from _: URL,
            source _: BrowserTabMigrationSource
        ) async throws -> BrowserPortableImport {
            importToReturn
        }

        func finishPortableExportPreparation() {
            portableExportContinuation?.resume(
                returning: BrowserPortableArchiveDocument(
                    data: Data([0x7B, 0x7D])
                )
            )
            portableExportContinuation = nil
        }
    }
}
