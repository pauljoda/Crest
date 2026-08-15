import CryptoKit
import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeWebStoreTests: XCTestCase {
    private static let backgroundEvictionIdleSeconds = 45
    private let darkReaderID = "eimadpbcbfnmbkopoojfekhnkhdbieeh"

    func testStoreItemRecognizesDarkReaderAndRejectsUntrustedLookalikes() throws {
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
                )!
            )
        )

        XCTAssertEqual(item.id.rawValue, darkReaderID)
        XCTAssertEqual(item.slug, "dark-reader")
        XCTAssertEqual(
            item.storeURL.absoluteString,
            "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
        )
        XCTAssertNil(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "http://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
                )!
            )
        )
        XCTAssertNil(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com.evil.test/detail/dark-reader/\(darkReaderID)"
                )!
            )
        )
        XCTAssertNil(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/dark-reader/not-an-extension-id"
                )!
            )
        )
    }

    func testUpdateRequestUsesTheOfficialCRX3RedirectEndpoint() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let url = BrowserChromeWebStoreUpdateRequest.url(for: id)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value)
            }
        )

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "clients2.google.com")
        XCTAssertEqual(components.path, "/service/update2/crx")
        XCTAssertEqual(query["response"]!, "redirect")
        XCTAssertEqual(query["acceptformat"]!, "crx3")
        XCTAssertEqual(query["x"]!, "id=\(darkReaderID)&uc")
    }

    func testVerifierAcceptsADeveloperAndPublisherSignedCRX3() throws {
        let fixture = try signedFixture()
        let verifier = BrowserCRX3Verifier(
            requiredPublisherKeyHash: fixture.publisherKeyHash
        )

        let package = try verifier.verify(
            fixture.crxData,
            expectedID: fixture.extensionID
        )

        XCTAssertEqual(package.extensionID, fixture.extensionID)
        XCTAssertEqual(package.zipArchiveData, fixture.zipData)
        XCTAssertFalse(package.crxSHA256Hex.isEmpty)
        XCTAssertEqual(
            package.publisherKeyHashHex,
            fixture.publisherKeyHash.hexString
        )
    }

    func testVerifierRejectsAMismatchedStoreIDAndTampering() throws {
        let fixture = try signedFixture()
        let verifier = BrowserCRX3Verifier(
            requiredPublisherKeyHash: fixture.publisherKeyHash
        )
        let otherID = try XCTUnwrap(
            BrowserChromeExtensionID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        )

        XCTAssertThrowsError(
            try verifier.verify(fixture.crxData, expectedID: otherID)
        ) { error in
            XCTAssertEqual(
                error as? BrowserCRX3VerifierError,
                .extensionIDMismatch
            )
        }

        var tampered = fixture.crxData
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        XCTAssertThrowsError(
            try verifier.verify(tampered, expectedID: fixture.extensionID)
        ) { error in
            XCTAssertEqual(
                error as? BrowserCRX3VerifierError,
                .invalidSignature
            )
        }
    }

    func testVerifierRequiresThePinnedPublisherProof() throws {
        let fixture = try signedFixture(includesPublisherProof: false)
        let verifier = BrowserCRX3Verifier(
            requiredPublisherKeyHash: fixture.publisherKeyHash
        )

        XCTAssertThrowsError(
            try verifier.verify(
                fixture.crxData,
                expectedID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserCRX3VerifierError,
                .missingPublisherProof
            )
        }
    }

    func testVerifiedPackageStagesUnderTheChromeIdentityInItsSpace() throws {
        let fixture = try signedFixture()
        let package = try BrowserCRX3Verifier(
            requiredPublisherKeyHash: fixture.publisherKeyHash
        ).verify(fixture.crxData, expectedID: fixture.extensionID)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-chrome-package-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: root
        )
        let spaceID = SpaceID()

        let staged = try store.stage(package, in: spaceID)

        XCTAssertEqual(staged.extensionID, fixture.extensionID.rawValue)
        XCTAssertEqual(staged.resourceURL.pathExtension, "zip")
        XCTAssertEqual(try Data(contentsOf: staged.resourceURL), fixture.zipData)
        XCTAssertEqual(
            try store.resourceURL(
                packageName: staged.packageName,
                in: spaceID
            ),
            staged.resourceURL
        )
    }

    func testVerifiedPreparedDirectoryKeepsTheChromeIdentity() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-prepared-chrome-package-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let source = fileManager.temporaryDirectory.appending(
            path: "crest-prepared-chrome-source-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: source)
        }
        try fileManager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(
            to: source.appending(path: "manifest.json")
        )
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: root
        )
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))

        let staged = try store.stageVerifiedChromeResource(
            source,
            extensionID: id,
            in: SpaceID()
        )

        XCTAssertEqual(staged.extensionID, darkReaderID)
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: staged.resourceURL
                    .appending(path: "manifest.json").path
            )
        )
    }

    func testOnePasswordCompatibilityLayerPreparesItsModuleWorker() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-onepassword-compatibility-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let workerURL = root.appending(path: "background/background.js")
        try fileManager.createDirectory(
            at: workerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(to: workerURL)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "background": [
                "service_worker": "background/background.js",
                "type": "module",
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "manifest.json")
        )
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )

        XCTAssertTrue(
            try preparer.installNotificationCompatibilityLayer(
                in: root,
                extensionID: BrowserChromeWebStoreCompatibilityPackagePreparer
                    .onePasswordExtensionID
            )
        )

        let updatedData = try Data(
            contentsOf: root.appending(path: "manifest.json")
        )
        let updated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updatedData)
                as? [String: Any]
        )
        let background = try XCTUnwrap(
            updated["background"] as? [String: Any]
        )
        XCTAssertEqual(
            background["service_worker"] as? String,
            "background/background.js"
        )
        let preparedWorker = try String(
            contentsOf: workerURL,
            encoding: .utf8
        )
        XCTAssertTrue(preparedWorker.contains("crestNotifications"))
        XCTAssertTrue(
            preparedWorker.contains("onCreatedNavigationTarget")
        )
        XCTAssertTrue(preparedWorker.contains("globalThis.started = true;"))
        XCTAssertFalse(preparedWorker.contains("await import"))
    }

    func testNotificationCompatibilityLayerIsLimitedToVerifiedOnePassword() {
        XCTAssertTrue(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresNotificationCompatibilityLayer(
                    extensionID:
                        BrowserChromeWebStoreCompatibilityPackagePreparer
                        .onePasswordExtensionID,
                    requestedPermissions: [
                        "nativeMessaging",
                        "notifications",
                    ]
                )
        )
        XCTAssertFalse(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresNotificationCompatibilityLayer(
                    extensionID: darkReaderID,
                    requestedPermissions: [
                        "nativeMessaging",
                        "notifications",
                    ]
                )
        )
    }

    func testICloudPasswordsCompatibilityLayerProvidesMissingHistoryEvent()
        throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-icloud-passwords-compatibility-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let workerURL = root.appending(path: "background.js")
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(to: workerURL)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "background": ["service_worker": "background.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "manifest.json")
        )
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )

        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                extensionID: BrowserChromeWebStoreCompatibilityPackagePreparer
                    .iCloudPasswordsExtensionID
            )
        )

        let preparedWorker = try String(
            contentsOf: workerURL,
            encoding: .utf8
        )
        XCTAssertTrue(preparedWorker.contains("onHistoryStateUpdated"))
        XCTAssertTrue(preparedWorker.contains("onTabReplaced"))
        XCTAssertTrue(preparedWorker.contains("not_controllable"))
        XCTAssertTrue(preparedWorker.contains("globalThis.started = true;"))
    }

    func testStoredDarkReaderArchiveRestoresFromItsSignedPackage() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-dark-reader-restoration-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let archiveURL = root.appending(path: "dark-reader.zip")
        try Data("stored package".utf8).write(to: archiveURL)
        let compatibilityPreparer =
            BrowserChromeWebStoreCompatibilityPackagePreparer(
                fileManager: fileManager,
                expandArchive: { _, _ in
                    XCTFail(
                        "Dark Reader must restore from its signed package."
                    )
                }
            )
        let preparer = BrowserChromeWebStoreStoredResourcePreparer(
            compatibilityPreparer: compatibilityPreparer
        )
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let source = BrowserChromeWebStoreSource(
            extensionID: id,
            storeURL: try XCTUnwrap(
                URL(
                    string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
                )
            ),
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: String(repeating: "b", count: 64)
        )
        let storedInstallation = installation(
            id: darkReaderID,
            spaceID: SpaceID(),
            source: .chromeWebStore(source),
            requestedPermissions: ["storage", "alarms", "contextMenus"]
        )

        let prepared = try preparer.prepare(
            resourceURL: archiveURL,
            installation: storedInstallation
        )

        XCTAssertEqual(prepared.resourceURL, archiveURL)
        XCTAssertNil(prepared.retainedAccess)
        XCTAssertFalse(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresCompatibilityLayer(
                    extensionID: darkReaderID,
                    requestedPermissions: storedInstallation
                        .requestedPermissions
                )
        )
    }

    func testStoredICloudPasswordsArchiveRestoresThroughCompatibilityDirectory()
        throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-icloud-passwords-restoration-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let archiveURL = root.appending(path: "icloud-passwords.zip")
        try Data("stored package".utf8).write(to: archiveURL)
        let compatibilityPreparer =
            BrowserChromeWebStoreCompatibilityPackagePreparer(
                fileManager: fileManager,
                expandArchive: { archive, destination in
                    XCTAssertEqual(archive, archiveURL)
                    let workerURL = destination.appending(
                        path: "background/index.js"
                    )
                    try fileManager.createDirectory(
                        at: workerURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("globalThis.started = true;".utf8).write(
                        to: workerURL
                    )
                    let manifest: [String: Any] = [
                        "manifest_version": 3,
                        "background": [
                            "service_worker": "background/index.js"
                        ],
                    ]
                    try JSONSerialization.data(withJSONObject: manifest)
                        .write(
                            to: destination.appending(path: "manifest.json")
                        )
                }
            )
        let preparer = BrowserChromeWebStoreStoredResourcePreparer(
            compatibilityPreparer: compatibilityPreparer
        )
        let iCloudPasswordsID =
            BrowserChromeWebStoreCompatibilityPackagePreparer
            .iCloudPasswordsExtensionID
        let id = try XCTUnwrap(BrowserChromeExtensionID(iCloudPasswordsID))
        let source = BrowserChromeWebStoreSource(
            extensionID: id,
            storeURL: try XCTUnwrap(
                URL(
                    string: "https://chromewebstore.google.com/detail/icloud-passwords/\(iCloudPasswordsID)"
                )
            ),
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: String(repeating: "b", count: 64)
        )
        let storedInstallation = installation(
            id: iCloudPasswordsID,
            spaceID: SpaceID(),
            source: .chromeWebStore(source),
            requestedPermissions: ["nativeMessaging", "webNavigation"]
        )

        let prepared = try preparer.prepare(
            resourceURL: archiveURL,
            installation: storedInstallation
        )

        XCTAssertNotEqual(prepared.resourceURL, archiveURL)
        XCTAssertNotNil(prepared.retainedAccess)
        XCTAssertTrue(fileManager.fileExists(atPath: archiveURL.path))
        let preparedWorker = try String(
            contentsOf: prepared.resourceURL.appending(
                path: "background/index.js"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(preparedWorker.contains("onHistoryStateUpdated"))
        XCTAssertTrue(preparedWorker.contains("globalThis.started = true;"))
    }

    func testChromeSourceRoundTripsAndRejectsIdentityMismatch() throws {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let spaceID = SpaceID()
        let source = BrowserChromeWebStoreSource(
            extensionID: id,
            storeURL: URL(
                string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
            )!,
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString
        )
        var record = installation(
            id: darkReaderID,
            spaceID: spaceID,
            source: .chromeWebStore(source)
        )

        XCTAssertTrue(registry.upsert(record))
        XCTAssertEqual(
            BrowserExtensionRegistry(persistence: persistence)
                .installation(extensionID: darkReaderID, in: spaceID),
            record
        )

        record = installation(
            id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            spaceID: spaceID,
            source: .chromeWebStore(source)
        )
        XCTAssertFalse(registry.upsert(record))
    }

    func testRuntimeIdentifierPreservesVerifiedChromeIdentityOnly() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let source = BrowserChromeWebStoreSource(
            extensionID: id,
            storeURL: URL(
                string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
            )!,
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString
        )
        let spaceID = SpaceID()

        XCTAssertEqual(
            BrowserExtensionRuntimeIdentifierPolicy.identifier(
                extensionID: darkReaderID,
                source: .chromeWebStore(source),
                spaceID: spaceID
            ),
            darkReaderID
        )
        XCTAssertEqual(
            BrowserExtensionRuntimeIdentifierPolicy.identifier(
                extensionID: "local.probe",
                source: .unpackedPackage,
                spaceID: spaceID
            ),
            "local.probe.space.\(spaceID.rawValue.uuidString.lowercased())"
        )
    }

    func testContentBridgeAdvertisesCrestOnlyOnTheTrustedStore() {
        XCTAssertTrue(
            BrowserChromeWebStoreContentBridge.source.contains("Add to Crest")
        )
        XCTAssertTrue(
            BrowserChromeWebStoreContentBridge.source.contains(
                "chromewebstore.google.com"
            )
        )
        XCTAssertTrue(
            BrowserChromeWebStoreContentBridge.source.contains(
                BrowserChromeWebStoreContentBridge.messageHandlerName
            )
        )
        XCTAssertTrue(
            BrowserChromeWebStoreContentBridge.source.contains(
                BrowserChromeWebStoreInstallNavigation.scheme
            )
        )
    }

    func testInstallNavigationRequiresTheCurrentTrustedStoreItem() throws {
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
                )!
            )
        )
        let navigationURL = BrowserChromeWebStoreInstallNavigation.url(
            for: item.id
        )

        XCTAssertEqual(
            BrowserChromeWebStoreInstallNavigation.item(
                for: navigationURL,
                currentURL: item.storeURL
            ),
            item
        )
        XCTAssertNil(
            BrowserChromeWebStoreInstallNavigation.item(
                for: navigationURL,
                currentURL: URL(
                    string: "https://chromewebstore.google.com.evil.test/detail/dark-reader/\(darkReaderID)"
                )!
            )
        )
        XCTAssertNil(
            BrowserChromeWebStoreInstallNavigation.item(
                for: BrowserChromeWebStoreInstallNavigation.url(
                    for: try XCTUnwrap(
                        BrowserChromeExtensionID(
                            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                        )
                    )
                ),
                currentURL: item.storeURL
            )
        )
    }

    func testRejectedFirstInstallationRemovesProvisionalState() async throws {
        let fileManager = FileManager.default
        let fixture = try replacementInstallationFixture()
        defer { try? fileManager.removeItem(at: fixture.rootURL) }
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: fixture.packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        let space = BrowserSession.preview.spaces[0]
        let rejected = replacementCandidate(
            item: fixture.item,
            extensionID: fixture.extensionID,
            archiveData: fixture.archiveData,
            packageHash: String(repeating: "b", count: 64),
            publisherHash: String(repeating: "c", count: 64)
        )

        do {
            _ = try await pool.installChromeWebStoreExtension(
                rejected,
                in: space
            )
            XCTFail("An untrusted installation record was persisted.")
        } catch BrowserExtensionControllerPoolError
            .invalidInstallationRecord
        {
            // The registry is the final provenance boundary after runtime load.
        }

        XCTAssertNil(
            registry.installation(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )
        )
        XCTAssertNil(
            pool.loadedContext(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )
        )
        XCTAssertTrue(pool.extensions(in: space.id).isEmpty)
        let spacePackageURL = fixture.packageRootURL.appending(
            path: space.id.rawValue.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        XCTAssertTrue(
            (try? fileManager.contentsOfDirectory(
                atPath: spacePackageURL.path
            ))?.isEmpty ?? true
        )
    }

    func testRejectedReplacementRestoresThePreviousPackageAndContext()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try replacementInstallationFixture()
        defer { try? fileManager.removeItem(at: fixture.rootURL) }
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: fixture.packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        let space = BrowserSession.preview.spaces[0]
        let accepted = replacementCandidate(
            item: fixture.item,
            extensionID: fixture.extensionID,
            archiveData: fixture.archiveData,
            packageHash: String(repeating: "a", count: 64),
            publisherHash:
                BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString
        )

        _ = try await pool.installChromeWebStoreExtension(
            accepted,
            in: space
        )
        let originalPackageName = try XCTUnwrap(
            registry.installation(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )?.packageName
        )
        let rejected = replacementCandidate(
            item: fixture.item,
            extensionID: fixture.extensionID,
            archiveData: fixture.archiveData,
            packageHash: String(repeating: "b", count: 64),
            publisherHash: String(repeating: "c", count: 64)
        )
        do {
            _ = try await pool.installChromeWebStoreExtension(
                rejected,
                in: space
            )
            XCTFail("An untrusted replacement record was persisted.")
        } catch BrowserExtensionControllerPoolError
            .invalidInstallationRecord
        {
            // The registry is the final provenance boundary after runtime load.
        }

        XCTAssertEqual(
            registry.installation(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )?.packageName,
            originalPackageName
        )
        XCTAssertTrue(
            try XCTUnwrap(
                pool.loadedContext(
                    extensionID: fixture.extensionID.rawValue,
                    in: space.id
                )
            ).isLoaded
        )
        XCTAssertEqual(
            pool.extensions(in: space.id).map(\.id),
            [fixture.extensionID.rawValue]
        )
        let spacePackageURL = fixture.packageRootURL.appending(
            path: space.id.rawValue.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: spacePackageURL.path),
            [originalPackageName]
        )
    }

    func testLiveUpdateCheckAnswersTheCurrentPublishedVersionWhenEnabled()
        async throws
    {
        let integrationMarker = URL(
            filePath: "/tmp/CrestRunChromeStoreIntegration"
        )
        guard
            ProcessInfo.processInfo.environment[
                "CREST_RUN_CHROME_STORE_INTEGRATION"
            ] == "1"
                || FileManager.default.fileExists(
                    atPath: integrationMarker.path
                )
        else {
            throw XCTSkip(
                "Set CREST_RUN_CHROME_STORE_INTEGRATION=1 to verify the live Chrome Web Store update-check shape."
            )
        }
        let checker = BrowserChromeWebStoreUpdateChecker()

        let published = try await checker.publishedVersion(
            forExtension: darkReaderID
        )

        // The endpoint answers with a real Chrome version rather than an
        // opaque token, which is the whole premise of comparing locally.
        let version = try XCTUnwrap(published)
        XCTAssertNotNil(
            BrowserExtensionVersionPolicy.compare(version, "0.0"),
            "\(version) is not a readable Chrome version."
        )
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare(version, "0.0"),
            .orderedDescending
        )
        XCTAssertTrue(
            BrowserExtensionVersionPolicy.isUpgrade(from: "0.1", to: version)
        )
        XCTAssertFalse(
            BrowserExtensionVersionPolicy.isUpgrade(from: version, to: version)
        )

        // A delisted identifier is reported, not silently treated as current.
        do {
            _ = try await checker.publishedVersion(
                forExtension: String(repeating: "a", count: 32)
            )
            XCTFail("An unknown extension must not answer with a version.")
        } catch let error as BrowserChromeWebStoreUpdateCheckError {
            guard case .applicationUnavailable = error else {
                return XCTFail("Unexpected update-check failure \(error).")
            }
        }
    }

    func testUpdateTargetsCoverOnlyStoreSourcedInstallations() throws {
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(registry: registry)
        let space = BrowserSession.preview.spaces[0]
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID("abcdefghijklmnopabcdefghijklmnop")
        )
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/probe/\(extensionID.rawValue)"
                )!
            )
        )
        registry.upsert(
            installation(
                id: extensionID.rawValue,
                spaceID: space.id,
                source: .chromeWebStore(
                    BrowserChromeWebStoreSource(
                        extensionID: extensionID,
                        storeURL: item.storeURL,
                        crxSHA256Hex: String(repeating: "a", count: 64),
                        publisherKeyHashHex: BrowserCRX3Verifier
                            .chromeWebStorePublisherKeyHash.hexString
                    )
                ),
                version: "1.0",
                isEnabled: false
            )
        )
        registry.upsert(
            installation(
                id: "com.example.unpacked",
                spaceID: space.id,
                source: .unpackedPackage,
                version: "3.0",
                isEnabled: true
            )
        )
        registry.upsert(
            installation(
                id: "com.example.host.extension",
                spaceID: space.id,
                source: nil,
                version: "2.0",
                isEnabled: true
            )
        )

        let targets = pool.chromeWebStoreUpdateTargets()

        XCTAssertEqual(targets.map(\.extensionID), [extensionID.rawValue])
        XCTAssertEqual(targets.first?.installedVersion, "1.0")
        XCTAssertEqual(targets.first?.isEnabled, false)
        XCTAssertEqual(targets.first?.spaceID, space.id)
    }

    func testUpdaterRefusesATargetWithoutAVerifiableStoreSource() async throws {
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(registry: registry)
        let space = BrowserSession.preview.spaces[0]
        registry.upsert(
            installation(
                id: "com.example.unpacked",
                spaceID: space.id,
                source: .unpackedPackage,
                version: "1.0",
                isEnabled: true
            )
        )
        let updater = BrowserChromeWebStoreUpdater(
            pool: pool,
            provider: BrowserChromeWebStoreProvider { _ in
                XCTFail("An unverifiable source must not reach the network.")
                throw URLError(.badURL)
            },
            spaces: { [space] }
        )
        let target = BrowserExtensionUpdateTarget(
            extensionID: "com.example.unpacked",
            spaceID: space.id,
            displayName: "Unpacked Probe",
            installedVersion: "1.0",
            isEnabled: true
        )

        do {
            _ = try await updater.applyUpdate(to: target)
            XCTFail("An unpacked installation has no store identity.")
        } catch let error as BrowserChromeWebStoreUpdaterError {
            guard case .unverifiableSource = error else {
                return XCTFail("Unexpected updater failure \(error).")
            }
        }
    }

    func testUpdaterRefusesATargetWhoseSpaceIsGone() async throws {
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(registry: registry)
        let space = BrowserSession.preview.spaces[0]
        let updater = BrowserChromeWebStoreUpdater(
            pool: pool,
            provider: BrowserChromeWebStoreProvider { _ in
                XCTFail("A missing Space must not reach the network.")
                throw URLError(.badURL)
            },
            spaces: { [] }
        )
        let target = BrowserExtensionUpdateTarget(
            extensionID: "abcdefghijklmnopabcdefghijklmnop",
            spaceID: space.id,
            displayName: "Probe",
            installedVersion: "1.0",
            isEnabled: true
        )

        do {
            _ = try await updater.applyUpdate(to: target)
            XCTFail("A closed Space cannot receive an updated package.")
        } catch let error as BrowserChromeWebStoreUpdaterError {
            guard case .missingSpace = error else {
                return XCTFail("Unexpected updater failure \(error).")
            }
        }
    }

    func testUpdateKeepsPinningPermissionsShortcutsAndInstallDate()
        async throws
    {
        let fileManager = FileManager.default
        let original = try replacementInstallationFixture(version: "1.0")
        let upgraded = try replacementInstallationFixture(version: "2.0")
        defer {
            try? fileManager.removeItem(at: original.rootURL)
            try? fileManager.removeItem(at: upgraded.rootURL)
        }
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: original.packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        let space = BrowserSession.preview.spaces[0]
        let extensionID = original.extensionID.rawValue
        let publisherHash =
            BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString

        _ = try await pool.installChromeWebStoreExtension(
            replacementCandidate(
                item: original.item,
                extensionID: original.extensionID,
                archiveData: original.archiveData,
                packageHash: String(repeating: "a", count: 64),
                publisherHash: publisherHash,
                version: "1.0"
            ),
            in: space
        )
        let installed = try XCTUnwrap(
            registry.installation(extensionID: extensionID, in: space.id)
        )
        XCTAssertEqual(installed.version, "1.0")

        // Crest records a permission decision with the date it stops applying,
        // and its own grants never expire.
        let grantedAt = Date.distantFuture
        registry.setPinned(true, extensionID: extensionID, in: space.id)
        registry.setCommandShortcutOverride(
            .unassigned,
            commandID: "toggle-probe",
            extensionID: extensionID,
            in: space.id
        )
        registry.updatePermissionSnapshot(
            BrowserExtensionPermissionSnapshot(
                grantedPermissions: ["storage": grantedAt],
                deniedPermissions: ["tabs": grantedAt]
            ),
            extensionID: extensionID,
            in: space.id
        )
        let beforeUpdate = try XCTUnwrap(
            registry.installation(extensionID: extensionID, in: space.id)
        )

        let summary = try await pool.installChromeWebStoreExtension(
            replacementCandidate(
                item: upgraded.item,
                extensionID: upgraded.extensionID,
                archiveData: upgraded.archiveData,
                packageHash: String(repeating: "d", count: 64),
                publisherHash: publisherHash,
                version: "2.0"
            ),
            in: space
        )
        let afterUpdate = try XCTUnwrap(
            registry.installation(extensionID: extensionID, in: space.id)
        )

        XCTAssertEqual(summary.version, "2.0")
        XCTAssertEqual(afterUpdate.version, "2.0")
        XCTAssertEqual(afterUpdate.isPinned, true)
        XCTAssertTrue(summary.isPinned)
        XCTAssertEqual(
            afterUpdate.commandShortcutOverrides?["toggle-probe"],
            .unassigned
        )
        XCTAssertEqual(afterUpdate.installedAt, beforeUpdate.installedAt)
        XCTAssertTrue(afterUpdate.isEnabled)
        // The decisions carry across the replacement. WebKit re-times them —
        // its snapshot records when a grant expires, not when it was made —
        // so the contract worth locking is which way each answer went.
        XCTAssertTrue(
            afterUpdate.permissionSnapshot.grantedPermissions.keys
                .contains("storage")
        )
        XCTAssertTrue(
            afterUpdate.permissionSnapshot.deniedPermissions.keys
                .contains("tabs")
        )
        XCTAssertFalse(
            afterUpdate.permissionSnapshot.grantedPermissions.keys
                .contains("tabs")
        )
        XCTAssertTrue(afterUpdate.modifiedAt >= beforeUpdate.modifiedAt)
    }

    func testLiveDarkReaderPackageVerifiesInspectsAndLoadsWhenEnabled()
        async throws
    {
        let integrationMarker = URL(
            filePath: "/tmp/CrestRunChromeStoreIntegration"
        )
        guard
            ProcessInfo.processInfo.environment[
                "CREST_RUN_CHROME_STORE_INTEGRATION"
            ] == "1"
                || FileManager.default.fileExists(
                    atPath: integrationMarker.path
                )
        else {
            throw XCTSkip(
                "Set CREST_RUN_CHROME_STORE_INTEGRATION=1 to verify the current Dark Reader package."
            )
        }
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
                )!
            )
        )
        let candidate = try await BrowserChromeWebStoreProvider()
            .candidate(for: item)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-dark-reader-live-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        pool.setNativeMessagingHandler(AuditNativeMessagingHandler())
        let testURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let tab = BrowserTab(
            title: "Dark Reader fixture",
            url: testURL,
            placement: .current
        )
        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Dark Reader",
            symbol: "moon.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let controller = pool.controller(for: space)
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(
                for: profile,
                webExtensionController: controller
            )
        )
        let pages = ChromeWebStorePageProviderSpy(
            webViews: [tab.id: webView]
        )
        pool.connect(browser: browser, pageProvider: pages)

        let summary = try await pool.installChromeWebStoreExtension(
            candidate,
            in: space
        )

        XCTAssertEqual(candidate.displayName, "Dark Reader")
        XCTAssertEqual(candidate.source.extensionID.rawValue, darkReaderID)
        XCTAssertTrue(candidate.errors.isEmpty)
        XCTAssertEqual(summary.displayName, "Dark Reader")
        XCTAssertTrue(summary.isLoaded)
        let context = try XCTUnwrap(
            pool.loadedContext(extensionID: darkReaderID, in: space.id)
        )
        XCTAssertEqual(context.uniqueIdentifier, darkReaderID)
        XCTAssertFalse(context.webExtension.hasPersistentBackgroundContent)
        XCTAssertTrue(
            [
                WKWebExtensionContext.PermissionStatus.grantedImplicitly,
                .grantedExplicitly,
            ].contains(context.permissionStatus(for: testURL))
        )
        let navigation = ChromeWebStoreNavigationWaiter(webView: webView)
        try await navigation.load(URLRequest(url: testURL))

        var darkReaderMode: String?
        for _ in 0..<400 {
            darkReaderMode =
                try await webView.evaluateJavaScript(
                    "document.documentElement.getAttribute('data-darkreader-mode')"
                ) as? String
            if darkReaderMode != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(
            darkReaderMode,
            "dynamic",
            "Dark Reader loaded but did not attach to an ordinary granted website. Runtime errors: \(context.errors.map(\.localizedDescription))"
        )
        let toolbarAction = try XCTUnwrap(
            pool.toolbarActions(in: space.id, tabID: tab.id).first
        )
        let popupWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let popupSourceView = NSView(
            frame: CGRect(x: 20, y: 540, width: 24, height: 24)
        )
        popupWindow.contentView?.addSubview(popupSourceView)
        popupWindow.orderFront(nil)
        defer {
            toolbarAction.action.closePopup()
            popupWindow.close()
        }
        pool.perform(
            toolbarAction,
            popupAnchor: BrowserExtensionPopupAnchor(
                sourceView: popupSourceView
            )
        )
        for _ in 0..<200
        where toolbarAction.action.popupPopover?.isShown != true {
            try await Task.sleep(for: .milliseconds(25))
        }
        let popupWebView = try XCTUnwrap(toolbarAction.action.popupWebView)
        var popupIsReady = false
        for _ in 0..<200 {
            popupIsReady =
                try await popupWebView.evaluateJavaScript(
                    """
                    (() => {
                        const loader = document.querySelector('.loader');
                        // A missing loader means the popup document has not
                        // parsed yet, so it must not count as readiness.
                        if (loader === null) { return false; }
                        return loader.classList.contains('loader--complete');
                    })()
                    """
                ) as? Bool == true
            if popupIsReady { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let popupText =
            try await popupWebView.evaluateJavaScript(
                "document.body.innerText"
            ) as? String
        XCTAssertTrue(
            popupIsReady,
            "Dark Reader’s signed popup did not leave its startup loader within five seconds. Text: \(popupText ?? "missing"). Runtime errors: \(context.errors.map(\.localizedDescription))"
        )
        pool.perform(
            toolbarAction,
            popupAnchor: BrowserExtensionPopupAnchor(
                sourceView: popupSourceView
            )
        )
        for _ in 0..<200
        where toolbarAction.action.popupPopover?.isShown == true {
            try await Task.sleep(for: .milliseconds(25))
        }
        pool.perform(
            toolbarAction,
            popupAnchor: BrowserExtensionPopupAnchor(
                sourceView: popupSourceView
            )
        )
        for _ in 0..<200
        where toolbarAction.action.popupPopover?.isShown != true {
            try await Task.sleep(for: .milliseconds(25))
        }
        let reopenedPopupWebView = try XCTUnwrap(
            toolbarAction.action.popupWebView
        )
        popupIsReady = false
        for _ in 0..<200 {
            popupIsReady =
                try await reopenedPopupWebView.evaluateJavaScript(
                    """
                    (() => {
                        const loader = document.querySelector('.loader');
                        return loader === null
                            || loader.classList.contains('loader--complete');
                    })()
                    """
                ) as? Bool == true
            if popupIsReady { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let reopenedPopupText =
            try await reopenedPopupWebView.evaluateJavaScript(
                "document.body.innerText"
            ) as? String
        XCTAssertTrue(
            popupIsReady,
            "Dark Reader’s signed popup returned to its startup loader after reopening. Text: \(reopenedPopupText ?? "missing"). Runtime errors: \(context.errors.map(\.localizedDescription))"
        )

        pool.perform(
            toolbarAction,
            popupAnchor: BrowserExtensionPopupAnchor(
                sourceView: popupSourceView
            )
        )
        for _ in 0..<200
        where toolbarAction.action.popupPopover?.isShown == true {
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .seconds(Self.backgroundEvictionIdleSeconds))
        pool.perform(
            toolbarAction,
            popupAnchor: BrowserExtensionPopupAnchor(
                sourceView: popupSourceView
            )
        )
        for _ in 0..<400
        where toolbarAction.action.popupPopover?.isShown != true {
            try await Task.sleep(for: .milliseconds(25))
        }
        let restartedPopupWebView = try XCTUnwrap(
            toolbarAction.action.popupWebView
        )
        popupIsReady = false
        for _ in 0..<400 {
            popupIsReady =
                try await restartedPopupWebView.evaluateJavaScript(
                    """
                    (() => {
                        const loader = document.querySelector('.loader');
                        return loader === null
                            || loader.classList.contains('loader--complete');
                    })()
                    """
                ) as? Bool == true
            if popupIsReady { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let restartedPopupText =
            try await restartedPopupWebView.evaluateJavaScript(
                "document.body.innerText"
            ) as? String
        XCTAssertTrue(
            popupIsReady,
            "Dark Reader’s signed popup stayed on its startup loader after its nonpersistent background went idle. Text: \(restartedPopupText ?? "missing"). Runtime errors: \(context.errors.map(\.localizedDescription))"
        )

        guard
            case .chromeWebStore(let source) = registry.installation(
                extensionID: darkReaderID,
                in: space.id
            )?.source
        else {
            return XCTFail("Dark Reader did not retain Web Store provenance.")
        }
        XCTAssertEqual(source.extensionID.rawValue, darkReaderID)
    }

    func testCurrentPopularExtensionPackagesVerifyInspectAndReachExpectedRuntimeBoundary()
        async throws
    {
        let integrationMarker = URL(
            filePath: "/tmp/CrestRunPopularExtensionAudit"
        )
        guard
            ProcessInfo.processInfo.environment[
                "CREST_RUN_POPULAR_EXTENSION_AUDIT"
            ] == "1"
                || FileManager.default.fileExists(
                    atPath: integrationMarker.path
                )
        else {
            throw XCTSkip(
                "Set CREST_RUN_POPULAR_EXTENSION_AUDIT=1 to audit current signed Web Store packages."
            )
        }

        let extensions = [
            PopularExtension(
                name: "Dark Reader",
                slug: "dark-reader",
                id: darkReaderID
            ),
            PopularExtension(
                name: "uBlock Origin Lite",
                slug: "ublock-origin-lite",
                id: "ddkjiahejlhfcafbddmgiahcphecmpfh"
            ),
            PopularExtension(
                name: "Bitwarden",
                slug: "bitwarden-password-manager",
                id: "nngceckbapebfimnlniiiahkandclblb"
            ),
            PopularExtension(
                name: "1Password",
                slug: "1password-password-manager",
                id: "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
            ),
            PopularExtension(
                name: "Grammarly",
                slug: "grammarly-ai-writing-and",
                id: "kbfnbcaeplbcioakkpcpgfkobkghlhen"
            ),
            PopularExtension(
                name: "React Developer Tools",
                slug: "react-developer-tools",
                id: "fmkadmapgofadopljbjfkapdkoienihi"
            ),
            PopularExtension(
                name: "SponsorBlock",
                slug: "sponsorblock-for-youtube",
                id: "mnjggcdmjocbbbhaepdhchncahnbgone"
            ),
            PopularExtension(
                name: "Tampermonkey",
                slug: "tampermonkey",
                id: "dhdgffkkebhmkfjojejmpbldmpobfkfo"
            ),
            PopularExtension(
                name: "iCloud Passwords",
                slug: "icloud-passwords",
                id: "pejdijmoenmkgeppbflobdenhhabjlaj"
            ),
        ]
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-popular-extension-audit-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        pool.setNativeMessagingHandler(AuditNativeMessagingHandler())
        let space = BrowserSession.preview.spaces[0]
        let provider = BrowserChromeWebStoreProvider(
            nativeMessagingCapability: .available
        )

        for popularExtension in extensions {
            let item = try XCTUnwrap(
                BrowserChromeWebStoreItem(url: popularExtension.storeURL)
            )
            let candidate = try await provider.candidate(for: item)
            XCTAssertEqual(
                candidate.source.extensionID.rawValue,
                popularExtension.id
            )

            if candidate.compatibility.canRun {
                let summary = try await pool.installChromeWebStoreExtension(
                    candidate,
                    in: space
                )
                try await Task.sleep(for: .milliseconds(350))
                let context = try XCTUnwrap(
                    pool.loadedContext(
                        extensionID: popularExtension.id,
                        in: space.id
                    )
                )
                XCTAssertTrue(summary.isLoaded)
                XCTAssertTrue(context.isLoaded)
                print(
                    "CREST_EXTENSION_AUDIT|\(popularExtension.name)|\(candidate.version ?? "unknown")|loaded|permissions=\(candidate.requestedPermissions.joined(separator: ","))|manifestErrors=\(candidate.errors.joined(separator: ";"))|runtimeErrors=\(context.errors.map(\.localizedDescription).joined(separator: ";"))|unsupported=\(context.unsupportedAPIs.sorted().joined(separator: ","))"
                )
                try await pool.removeExtension(
                    extensionID: popularExtension.id,
                    from: space
                )
            } else {
                do {
                    _ = try await pool.installChromeWebStoreExtension(
                        candidate,
                        in: space
                    )
                    XCTFail(
                        "\(popularExtension.name) crossed a blocking compatibility boundary."
                    )
                } catch {
                    XCTAssertTrue(error is BrowserExtensionCompatibilityError)
                }
                print(
                    "CREST_EXTENSION_AUDIT|\(popularExtension.name)|\(candidate.version ?? "unknown")|blocked|permissions=\(candidate.requestedPermissions.joined(separator: ","))|reason=\(candidate.compatibility.blockingIssues.map(\.message).joined(separator: ";"))"
                )
            }
        }
    }

    private struct PopularExtension {
        let name: String
        let slug: String
        let id: String

        var storeURL: URL {
            URL(
                string: "https://chromewebstore.google.com/detail/\(slug)/\(id)"
            )!
        }
    }

    private func installation(
        id: String,
        spaceID: SpaceID,
        source: BrowserExtensionInstallationSource,
        requestedPermissions: [String] = ["storage"]
    ) -> BrowserExtensionInstallation {
        BrowserExtensionInstallation(
            id: id,
            spaceID: spaceID,
            packageName: "\(id).zip",
            source: source,
            displayName: "Dark Reader",
            version: "1.0",
            requestedPermissions: requestedPermissions,
            requestedHosts: ["<all_urls>"],
            unsupportedAPIs: [],
            errors: [],
            isEnabled: true,
            permissionSnapshot: .empty,
            installedAt: Date(timeIntervalSince1970: 10),
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func installation(
        id: String,
        spaceID: SpaceID,
        source: BrowserExtensionInstallationSource?,
        version: String?,
        isEnabled: Bool
    ) -> BrowserExtensionInstallation {
        BrowserExtensionInstallation(
            id: id,
            spaceID: spaceID,
            packageName: "\(id).package",
            source: source,
            displayName: "Probe \(id)",
            version: version,
            requestedPermissions: [],
            requestedHosts: [],
            unsupportedAPIs: [],
            errors: [],
            isEnabled: isEnabled,
            permissionSnapshot: .empty,
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func replacementCandidate(
        item: BrowserChromeWebStoreItem,
        extensionID: BrowserChromeExtensionID,
        archiveData: Data,
        packageHash: String,
        publisherHash: String,
        version: String = "1.0"
    ) -> BrowserChromeWebStoreCandidate {
        let source = BrowserChromeWebStoreSource(
            extensionID: extensionID,
            storeURL: item.storeURL,
            crxSHA256Hex: packageHash,
            publisherKeyHashHex: publisherHash
        )
        return BrowserChromeWebStoreCandidate(
            item: item,
            source: source,
            verifiedPackage: BrowserVerifiedCRX3Package(
                extensionID: extensionID,
                crxData: Data(),
                zipArchiveData: archiveData,
                crxSHA256Hex: packageHash,
                publisherKeyHashHex: publisherHash
            ),
            displayName: "Replacement Rollback Probe",
            version: version,
            displayDescription: nil,
            requestedPermissions: [],
            requestedHosts: [],
            errors: [],
            iconPayload: nil,
            hasOptionsPage: false,
            hasCommands: false,
            hasContentModificationRules: false,
            nativeMessagingCapability: .available,
            iCloudPasswordsCapability: .available
        )
    }

    private func replacementInstallationFixture(
        version: String = "1.0"
    ) throws -> (
        rootURL: URL,
        packageRootURL: URL,
        archiveData: Data,
        extensionID: BrowserChromeExtensionID,
        item: BrowserChromeWebStoreItem
    ) {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-extension-replacement-rollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = rootURL.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        let archiveURL = rootURL.appending(path: "extension.zip")
        let packageRootURL = rootURL.appending(
            path: "Packages",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Replacement Rollback Probe",
            "version": version,
            "permissions": ["storage", "tabs"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: sourceURL.appending(path: "manifest.json")
        )
        try createZipArchive(from: sourceURL, at: archiveURL)
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/rollback-probe/\(extensionID.rawValue)"
                )!
            )
        )
        return (
            rootURL: rootURL,
            packageRootURL: packageRootURL,
            archiveData: try Data(contentsOf: archiveURL),
            extensionID: extensionID,
            item: item
        )
    }

    private func createZipArchive(
        from sourceURL: URL,
        at archiveURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            sourceURL.path,
            archiveURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func signedFixture(
        includesPublisherProof: Bool = true
    ) throws -> SignedFixture {
        let developer = P256.Signing.PrivateKey()
        let publisher = P256.Signing.PrivateKey()
        let developerKey = developer.publicKey.derRepresentation
        let publisherKey = publisher.publicKey.derRepresentation
        let developerHash = Data(SHA256.hash(data: developerKey))
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                chromeExtensionID(from: developerHash.prefix(16))
            )
        )
        let extensionIDBytes = Data(developerHash.prefix(16))
        let signedHeader = protobufField(1, bytes: extensionIDBytes)
        let zipData =
            Data([0x50, 0x4b, 0x03, 0x04])
            + Data("signed crest extension fixture".utf8)
        let signedMessage =
            Data("CRX3 SignedData\0".utf8)
            + littleEndian(UInt32(signedHeader.count))
            + signedHeader
            + zipData
        let developerSignature = try developer.signature(
            for: signedMessage
        ).derRepresentation
        let publisherSignature = try publisher.signature(
            for: signedMessage
        ).derRepresentation
        let developerProof =
            protobufField(1, bytes: developerKey)
            + protobufField(2, bytes: developerSignature)
        let publisherProof =
            protobufField(1, bytes: publisherKey)
            + protobufField(2, bytes: publisherSignature)
        var header = protobufField(3, bytes: developerProof)
        if includesPublisherProof {
            header += protobufField(3, bytes: publisherProof)
        }
        header += protobufField(10_000, bytes: signedHeader)
        let crxData =
            Data("Cr24".utf8)
            + littleEndian(UInt32(3))
            + littleEndian(UInt32(header.count))
            + header
            + zipData
        return SignedFixture(
            extensionID: extensionID,
            publisherKeyHash: Data(SHA256.hash(data: publisherKey)),
            crxData: crxData,
            zipData: zipData
        )
    }

    private func protobufField(_ field: Int, bytes: Data) -> Data {
        var result = varint(UInt64(field << 3 | 2))
        result += varint(UInt64(bytes.count))
        result += bytes
        return result
    }

    private func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }

    private func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func chromeExtensionID(
        from bytes: Data.SubSequence
    ) -> String {
        bytes.flatMap { byte in
            [
                Character(UnicodeScalar(Int(byte >> 4) + 97)!),
                Character(UnicodeScalar(Int(byte & 0x0f) + 97)!),
            ]
        }.map(String.init).joined()
    }

    private struct SignedFixture {
        let extensionID: BrowserChromeExtensionID
        let publisherKeyHash: Data
        let crxData: Data
        let zipData: Data
    }
}

@MainActor
private final class ChromeWebStorePageProviderSpy:
    BrowserExtensionPageProviding
{
    let webViews: [TabID: WKWebView]

    init(webViews: [TabID: WKWebView]) {
        self.webViews = webViews
    }

    func extensionWebView(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> WKWebView? {
        webViews[tabID]
    }

    func extensionReaderModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState {
        .unavailable
    }

    func setExtensionReaderModeActive(
        _ isActive: Bool,
        for tabID: TabID,
        in spaceID: SpaceID
    ) async throws {}

    func extensionWindowGeometry(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry {
        .unavailable
    }

    func prepareExtensionSelection(session: BrowserSession) {}

    func select(session: BrowserSession) {}
}

@MainActor
private final class ChromeWebStoreNavigationWaiter:
    NSObject,
    WKNavigationDelegate
{
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ request: URLRequest) async throws {
        guard let webView else {
            throw BrowserChromeWebStoreTestError.releasedWebView
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private enum BrowserChromeWebStoreTestError: Error {
    case releasedWebView
}

@MainActor
private final class AuditNativeMessagingHandler:
    BrowserExtensionNativeMessagingHandling
{
    let capability = BrowserExtensionNativeMessagingCapability.available

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionID: BrowserChromeExtensionID,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        replyHandler(nil, BrowserExtensionNativeMessagingError.unavailable)
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionID: BrowserChromeExtensionID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension Data {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
