import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionInstallationControllerTests: XCTestCase {
    func testReloadDropsRemovedManagedPermissionsAndKeepsCurrentConsent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manifest = source.appending(path: "manifest.json")
        try Data(
            #"{"manifest_version":3,"name":"Reload consent","version":"1","permissions":["idle","clipboardRead","storage"],"optional_permissions":["tabGroups"]}"#
                .utf8
        ).write(to: manifest)
        let space = BrowserSession.preview.spaces[0]
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(rootURL: root.appending(path: "Packages")), registry: registry)
        let installed = try await pool.loadUnpackedExtension(from: source, in: space)
        pool.setPermissionDecision(.allow, for: "tabGroups", extensionID: installed.id, in: space.id)
        pool.setPermissionDecision(.allow, for: "idle", extensionID: installed.id, in: space.id)
        pool.setPermissionDecision(.block, for: "clipboardRead", extensionID: installed.id, in: space.id)
        pool.setPermissionDecision(.block, for: "storage", extensionID: installed.id, in: space.id)
        try Data(
            #"{"manifest_version":3,"name":"Reload consent","version":"2","permissions":["storage"],"optional_permissions":["tabGroups"]}"#
                .utf8
        ).write(to: manifest)
        let reloaded = try await pool.loadUnpackedExtension(from: source, in: space)
        XCTAssertEqual(reloaded.id, installed.id)
        let snapshot = try XCTUnwrap(registry.installation(extensionID: installed.id, in: space.id)).permissionSnapshot
        XCTAssertEqual(snapshot.grantedPermissions["tabGroups"], .distantFuture)
        XCTAssertNil(snapshot.grantedPermissions["idle"])
        XCTAssertNil(snapshot.deniedPermissions["clipboardRead"])
        XCTAssertEqual(pool.permissionDecision(for: "storage", extensionID: installed.id, in: space.id), .block)
    }

    func testHostDecisionsRespectExpiryAndDenialPrecedence() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"manifest_version":3,"name":"Host consent","version":"1"}"#.utf8).write(
            to: source.appending(path: "manifest.json"))
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(rootURL: root.appending(path: "Packages")), registry: registry)
        let space = BrowserSession.preview.spaces[0]
        let installed = try await pool.loadUnpackedExtension(from: source, in: space)
        let host = "https://example.com/*"
        for (grant, denial, expected) in [
            (Date.distantPast, Date.distantPast, BrowserExtensionAccessDecision.ask),
            (.distantFuture, .distantFuture, .block),
            (.distantFuture, .distantPast, .allow),
            (.distantPast, .distantFuture, .block),
        ] {
            registry.updatePermissionSnapshot(
                .init(grantedHosts: [host: grant], deniedHosts: [host: denial]),
                extensionID: installed.id, in: space.id)
            XCTAssertEqual(pool.hostDecision(for: host, extensionID: installed.id, in: space.id), expected)
        }
    }

    func testCopyStopsWhenSpaceAccessChangesDuringPreparation() async throws {
        for locksSource in [true, false] {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appending(path: "Source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data(#"{"manifest_version":3,"name":"Copy consent","version":"1"}"#.utf8)
                .write(to: source.appending(path: "manifest.json"))
            let spaces = BrowserSession.preview.spaces
            var available = spaces
            let preparer = CopyAccessChangingPreparer()
            let registry = BrowserExtensionRegistry()
            let packageRoot = root.appending(path: "Packages")
            let pool = BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(rootURL: packageRoot), registry: registry,
                storedResourcePreparer: preparer)
            pool.installationSpaces = { available }
            let installed = try await pool.loadUnpackedExtension(from: source, in: spaces[0])
            preparer.onPrepare = {
                available.removeAll { $0.id == spaces[locksSource ? 0 : 1].id }
            }
            do {
                try await pool.copyExtension(extensionID: installed.id, from: spaces[0].id, to: [spaces[1].id])
                XCTFail("Access revoked during preparation must abort the copy")
            } catch {}
            XCTAssertNil(registry.installation(extensionID: installed.id, in: spaces[1].id))
            XCTAssertNil(pool.runtimeContextController.loadedContext(extensionID: installed.id, in: spaces[1].id))
            XCTAssertNotNil(registry.installation(extensionID: installed.id, in: spaces[0].id))
            let destination = packageRoot.appending(path: spaces[1].id.rawValue.uuidString.lowercased())
            let retained = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
            XCTAssertTrue(retained.isEmpty, "Aborted copies must discard their staged packages")
        }
    }

    func testInstallReviewDefaultsToAllowAndPersistsOnlyReviewedChoices() throws {
        let permissions = ["storage", "declarativeNetRequest"]
        let hosts = ["https://example.com/*"]
        var review = BrowserExtensionInstallationPermissionPolicy.Review()
        XCTAssertTrue(review.allowsPermission("declarativeNetRequest"))
        XCTAssertTrue(review.allowsHost(hosts[0]))
        review.permissions = ["declarativeNetRequest": false, "unrequested": true]
        review.hosts[hosts[0]] = false
        let snapshot = BrowserExtensionInstallationPermissionPolicy.reviewedRequiredAccess(
            permissions: permissions, hosts: hosts, review: review)
        let restored = try JSONDecoder().decode(
            BrowserExtensionPermissionSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(Set(restored.grantedPermissions.keys), ["storage"])
        XCTAssertEqual(Set(restored.deniedPermissions.keys), ["declarativeNetRequest"])
        XCTAssertEqual(Set(restored.deniedHosts.keys), Set(hosts))
        XCTAssertTrue(restored.grantedHosts.isEmpty)

        var replacement = BrowserExtensionInstallationPermissionPolicy.Review(previousSnapshot: restored)
        XCTAssertFalse(replacement.allowsPermission("declarativeNetRequest"))
        XCTAssertFalse(replacement.allowsPermission("idle"))
        XCTAssertFalse(replacement.allowsHost(hosts[0]))
        XCTAssertEqual(
            BrowserExtensionInstallationPermissionPolicy.reviewedRequiredAccess(
                permissions: permissions + ["idle"], hosts: hosts, previous: restored, review: replacement), restored)
        replacement.permissions["idle"] = true
        let approved = BrowserExtensionInstallationPermissionPolicy.reviewedRequiredAccess(
            permissions: permissions + ["idle"], hosts: hosts, previous: restored, review: replacement)
        XCTAssertEqual(approved.grantedPermissions["idle"], .distantFuture)
        XCTAssertEqual(approved.deniedPermissions, restored.deniedPermissions)
    }

    func testCopiesKeepConsentAndPackagesIsolatedAndNeverReplaceAnExistingInstallation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Source")
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data(#"{"manifest_version":3,"name":"Space copy","version":"1.0","permissions":["storage","idle"]}"#.utf8)
            .write(to: sourceURL.appending(path: "manifest.json"))
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(rootURL: root.appending(path: "Packages")), registry: registry)
        let spaces = BrowserSession.preview.spaces
        pool.installationSpaces = { spaces }
        let installed = try await pool.loadUnpackedExtension(from: sourceURL, in: spaces[0])
        try await pool.setPermissionDecision(.allow, for: "storage", extensionID: installed.id, in: spaces[0])
        try await pool.setPermissionDecision(.block, for: "idle", extensionID: installed.id, in: spaces[0])
        let sourceData = try XCTUnwrap(pool.extensionWebsiteDataStore(in: spaces[0].id))
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "source-only", .value: "disposable", .domain: "example.com", .path: "/",
            ]))
        await sourceData.httpCookieStore.setCookie(cookie)
        let original = try XCTUnwrap(registry.installation(extensionID: installed.id, in: spaces[0].id))
        do {
            try await pool.copyExtension(extensionID: installed.id, from: spaces[0].id, to: [spaces[1].id, SpaceID()])
            XCTFail("An unavailable destination must report a partial failure.")
        } catch {}
        let copy = try XCTUnwrap(registry.installation(extensionID: installed.id, in: spaces[1].id))
        let destinationData = try XCTUnwrap(pool.extensionWebsiteDataStore(in: spaces[1].id))
        XCTAssertFalse(sourceData === destinationData)
        let destinationCookies = await destinationData.httpCookieStore.allCookies()
        XCTAssertFalse(destinationCookies.contains { $0.name == "source-only" })
        XCTAssertEqual(copy.permissionSnapshot, original.permissionSnapshot)
        XCTAssertEqual(copy.source, original.source)
        XCTAssertNotEqual(copy.packageName, original.packageName)
        let originalURL = try pool.persistenceController.resourceURL(
            packageName: original.packageName, in: spaces[0].id)
        let copyURL = try pool.persistenceController.resourceURL(packageName: copy.packageName, in: spaces[1].id)
        try Data("destination only".utf8).write(to: copyURL.appending(path: "copy-only.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appending(path: "copy-only.txt").path))
        XCTAssertFalse(
            pool.runtimeContextController.loadedContext(extensionID: installed.id, in: spaces[0].id)
                === pool.runtimeContextController.loadedContext(extensionID: installed.id, in: spaces[1].id))
        try await pool.setPermissionDecision(.allow, for: "idle", extensionID: installed.id, in: spaces[1])
        try await pool.copyExtension(extensionID: installed.id, from: spaces[0].id, to: [spaces[1].id])
        XCTAssertEqual(pool.permissionDecision(for: "idle", extensionID: installed.id, in: spaces[1].id), .allow)
        XCTAssertEqual(pool.permissionDecision(for: "idle", extensionID: installed.id, in: spaces[0].id), .block)
        pool.installationSpaces = { [spaces[0]] }
        do {
            try await pool.copyExtension(extensionID: installed.id, from: spaces[0].id, to: [spaces[1].id])
            XCTFail("Unavailable Spaces must be rejected, including stale selections.")
        } catch {}
    }

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

@MainActor
private final class CopyAccessChangingPreparer: BrowserExtensionStoredResourcePreparing {
    var onPrepare: (() -> Void)?

    func prepare(resourceURL: URL, request: BrowserExtensionStoredResourcePreparationRequest) async throws
        -> BrowserExtensionStoredResource
    {
        await Task.yield()
        onPrepare?()
        return BrowserExtensionStoredResource(resourceURL: resourceURL)
    }
}
