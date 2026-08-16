import WebKit
import XCTest

@testable import Crest

/// Composes startup the way the app does and asserts an installed extension
/// actually ends up loaded.
///
/// The existing restoration coverage exercises
/// `BrowserExtensionControllerPool` on its own. That leaves the seam this suite
/// covers: the real launch runs the pool *through* `BrowserPagePool`, connected
/// to a `BrowserStore`, and it selects a tab before it restores — the order in
/// `CrestApp` composition and `BrowserRootModel.prepareBrowser`. A regression
/// that only appears once those are wired together would pass every suite that
/// builds the pool by hand.
@MainActor
final class BrowserExtensionStartupPipelineTests: XCTestCase {

    /// The whole pipeline, in the app's order: connect, select, then restore.
    func testAnInstalledExtensionLoadsWhenStartupSelectsBeforeRestoring() async throws {
        let installed = try await makeInstalledExtension()
        defer { installed.cleanUp() }

        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [installed.space],
                selectedSpaceID: installed.space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let extensions = installed.makeRelaunchedPool()
        let pages = BrowserPagePool(extensionControllerPool: extensions)
        // CrestApp.swift composition order.
        extensions.connect(browser: browser, pageProvider: pages)

        // BrowserRootModel: the root view selects before `prepareBrowser` runs,
        // so the controller already exists and cards are already presented by
        // the time restoration is asked for.
        pages.select(session: browser.session)
        await pages.restoreExtensions(in: browser.session)

        let context = try XCTUnwrap(
            extensions.loadedContext(
                extensionID: installed.extensionID,
                in: installed.space.id
            ),
            "Startup finished with no loaded context for an enabled extension."
        )
        XCTAssertTrue(context.isLoaded)
    }

    /// The same pipeline with restoration first, which is the order a launch
    /// takes when the restored tab is not activated on startup.
    func testAnInstalledExtensionLoadsWhenStartupRestoresBeforeSelecting() async throws {
        let installed = try await makeInstalledExtension()
        defer { installed.cleanUp() }

        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [installed.space],
                selectedSpaceID: installed.space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let extensions = installed.makeRelaunchedPool()
        let pages = BrowserPagePool(extensionControllerPool: extensions)
        extensions.connect(browser: browser, pageProvider: pages)

        await pages.restoreExtensions(in: browser.session)
        pages.select(session: browser.session)

        let context = try XCTUnwrap(
            extensions.loadedContext(
                extensionID: installed.extensionID,
                in: installed.space.id
            )
        )
        XCTAssertTrue(context.isLoaded)
    }

    /// A private pool restores nothing, so its silence is expected rather than
    /// a symptom. Pinned so the diagnostic gate keeps describing it.
    func testAPrivatePoolRestoresNothing() async throws {
        let installed = try await makeInstalledExtension()
        defer { installed.cleanUp() }

        let extensions = installed.makeRelaunchedPool()
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            extensionControllerPool: extensions
        )

        await pages.restoreExtensions(
            in: BrowserSession(
                spaces: [installed.space],
                selectedSpaceID: installed.space.id
            )
        )

        XCTAssertNil(
            extensions.loadedContext(
                extensionID: installed.extensionID,
                in: installed.space.id
            )
        )
    }

    /// The quietest gate in the pipeline: a record filed under a Space the
    /// session no longer carries loads nothing at all.
    ///
    /// This is the shape a whole extension set disappears in, and it is a
    /// legitimate outcome rather than a defect — which is precisely why the
    /// startup log has to name it.
    func testARecordForAnAbsentSpaceLoadsNothing() async throws {
        let installed = try await makeInstalledExtension()
        defer { installed.cleanUp() }

        let extensions = installed.makeRelaunchedPool()
        let pages = BrowserPagePool(extensionControllerPool: extensions)
        // A session whose Spaces carry different identities than the record.
        let replacement = BrowserSpace(
            id: SpaceID(),
            profile: installed.space.profile,
            name: installed.space.name,
            symbol: installed.space.symbol,
            accent: installed.space.accent,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )

        await pages.restoreExtensions(
            in: BrowserSession(
                spaces: [replacement],
                selectedSpaceID: replacement.id
            )
        )

        XCTAssertNil(
            extensions.loadedContext(
                extensionID: installed.extensionID,
                in: installed.space.id
            )
        )
    }

    // MARK: - Support

    /// An extension installed and persisted by one pool, plus everything needed
    /// to stand a *fresh* pool over the same records — the relaunch.
    @MainActor
    private struct InstalledExtension {
        let extensionID: String
        let space: BrowserSpace
        let root: URL
        let persistence: InMemoryBrowserExtensionRegistryPersistence

        func makeRelaunchedPool() -> BrowserExtensionControllerPool {
            BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(
                    fileManager: .default,
                    rootURL: root,
                    removesRootOnDeinit: false
                ),
                registry: BrowserExtensionRegistry(persistence: persistence)
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeInstalledExtension() async throws -> InstalledExtension {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-extension-startup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let space = BrowserSession.preview.spaces[0]
        let installer = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: .default,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )
        let summary = try await installer.loadUnpackedExtension(
            from: fixtureURL,
            in: space
        )
        return InstalledExtension(
            extensionID: summary.id,
            space: space,
            root: root,
            persistence: persistence
        )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(
                path: "Fixtures/SpaceProbeExtension",
                directoryHint: .isDirectory
            )
    }
}
