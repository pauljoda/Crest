import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionInstallationControllerTests: XCTestCase {
    func testFailedUnpackedInstallationDiscardsItsStagedCopy() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-extension-installation-rollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = rootURL.appending(
            path: "InvalidSource",
            directoryHint: .isDirectory
        )
        let packageRootURL = rootURL.appending(
            path: "Packages",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: true
        )
        try Data("{".utf8).write(
            to: sourceURL.appending(path: "manifest.json")
        )
        defer { try? fileManager.removeItem(at: rootURL) }

        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        let space = BrowserSession.preview.spaces[0]

        do {
            _ = try await pool.loadUnpackedExtension(
                from: sourceURL,
                in: space
            )
            XCTFail("An invalid extension manifest was installed.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertTrue(registry.installations.isEmpty)
        XCTAssertTrue(pool.extensions(in: space.id).isEmpty)
        XCTAssertTrue(
            regularFiles(in: packageRootURL, fileManager: fileManager).isEmpty
        )
    }

    func testReimportingAnUnpackedFolderKeepsItsRowPinAndShortcuts()
        async throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-extension-reimport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = rootURL.appending(
            path: "ProbeSource",
            directoryHint: .isDirectory
        )
        let packageRootURL = rootURL.appending(
            path: "Packages",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: fixtureURL, to: sourceURL)

        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        let space = BrowserSession.preview.spaces[0]

        let first = try await pool.loadUnpackedExtension(
            from: sourceURL,
            in: space
        )
        pool.setPinned(true, extensionID: first.id, in: space.id)
        pool.setShortcut(
            BrowserShortcut(key: .character("j"), modifiers: [.command, .shift]),
            commandID: "addSite",
            extensionID: first.id,
            in: space.id
        )
        let firstPackageName = try XCTUnwrap(
            registry.installation(extensionID: first.id, in: space.id)?
                .packageName
        )

        let second = try await pool.loadUnpackedExtension(
            from: sourceURL,
            in: space
        )
        let installation = try XCTUnwrap(
            registry.installation(extensionID: second.id, in: space.id)
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(registry.installations(in: space.id).count, 1)
        XCTAssertTrue(installation.isPinned == true)
        XCTAssertEqual(
            installation.commandShortcutOverrides?["addSite"],
            .custom(
                BrowserShortcut(
                    key: .character("j"),
                    modifiers: [.command, .shift]
                )
            )
        )
        // The replaced stored copy is reclaimed rather than left behind.
        XCTAssertNotEqual(installation.packageName, firstPackageName)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath:
                    packageRootURL
                    .appending(
                        path: space.id.rawValue.uuidString.lowercased(),
                        directoryHint: .isDirectory
                    )
                    .appending(path: firstPackageName).path
            )
        )
    }

    func testMatrixHidesApplyAtLoadWithoutRatchetingIntoTheRecord()
        async throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-extension-unsupported-apis-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let packageRootURL = rootURL.appending(
            path: "Packages",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: rootURL) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let space = BrowserSession.preview.spaces[0]
        let hiddenAPI = "browser.webRequest.onAuthRequired"
        let extensionID: String
        let firstRuntimeHides: Set<String>

        do {
            let registry = BrowserExtensionRegistry(persistence: persistence)
            let pool = BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(
                    fileManager: fileManager,
                    rootURL: packageRootURL,
                    removesRootOnDeinit: false
                ),
                registry: registry
            )
            let summary = try await pool.loadUnpackedExtension(
                from: fixtureURL,
                in: space
            )
            extensionID = summary.id
            let context = try XCTUnwrap(
                pool.loadedContext(extensionID: extensionID, in: space.id)
            )
            let matrixHides =
                BrowserExtensionAPICompatibilityMatrix
                .unsupportedWebKitAPIs(
                    requestedPermissions: context.webExtension
                        .requestedPermissions
                        .map(\.rawValue)
                )

            XCTAssertTrue(
                matrixHides.contains(hiddenAPI),
                "The scenario needs the matrix to be hiding something."
            )
            // WebKit silently drops any path it does not recognize, so the
            // context reports a subset. What matters is that every hide it
            // does carry came from the matrix rather than from a record.
            XCTAssertTrue(
                context.unsupportedAPIs.isSubset(of: matrixHides),
                "The runtime hide list is the matrix computation."
            )
            XCTAssertTrue(
                Set(summary.unsupportedAPIs).isDisjoint(with: matrixHides),
                "A routing internal is not something a user can act on."
            )
            let installation = try XCTUnwrap(
                registry.installation(extensionID: extensionID, in: space.id)
            )
            XCTAssertTrue(
                installation.unsupportedAPIs.isEmpty,
                "Matrix hides must not be persisted into the record."
            )
            firstRuntimeHides = context.unsupportedAPIs

            // An older build ratcheted the hide list into the record. The
            // stale entry must not survive a load once it is Crest's to
            // recompute.
            registry.updateRuntimeSummary(
                displayName: installation.displayName,
                version: installation.version,
                requestedPermissions: installation.requestedPermissions,
                requestedHosts: installation.requestedHosts,
                unsupportedAPIs: [hiddenAPI],
                errors: installation.errors,
                extensionID: extensionID,
                in: space.id
            )
        }

        let restoredRegistry = BrowserExtensionRegistry(
            persistence: persistence
        )
        let restoredPool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: restoredRegistry
        )
        await restoredPool.restoreEnabledExtensions(in: [space])

        let restoredContext = try XCTUnwrap(
            restoredPool.loadedContext(extensionID: extensionID, in: space.id)
        )
        XCTAssertEqual(
            restoredContext.unsupportedAPIs,
            firstRuntimeHides,
            "The hide list is recomputed from the matrix on every load."
        )
        let restored = try XCTUnwrap(
            restoredRegistry.installation(
                extensionID: extensionID,
                in: space.id
            )
        )
        XCTAssertFalse(
            restored.unsupportedAPIs.contains(hiddenAPI),
            "An install carrying an older build's hide list heals on load."
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

    private func regularFiles(
        in rootURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        guard
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                (try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }
}
