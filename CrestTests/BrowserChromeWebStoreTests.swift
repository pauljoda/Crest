import CryptoKit
import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeWebStoreTests: XCTestCase {
    private static let backgroundEvictionIdleSeconds = 45
    private let darkReaderID = "eimadpbcbfnmbkopoojfekhnkhdbieeh"
    private var fixtureRuntimeIdentity: BrowserExtensionRuntimeIdentity {
        BrowserExtensionRuntimeIdentity(
            extensionID: "fixture-extension-id",
            uniqueIdentifier: "fixture-extension-id.space.personal",
            baseURL: URL(string: "crest-extension://fixture-runtime/")!
        )
    }

    private func generatedJavaScriptURL(
        in root: URL,
        prefix: String
    ) throws -> URL {
        let matches = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(prefix + "-")
                && $0.pathExtension == "js"
        }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

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

    func testVerifierReadsTheSignedIdentityForADirectCRXImport() throws {
        let fixture = try signedFixture()
        let verifier = BrowserCRX3Verifier(
            requiredPublisherKeyHash: fixture.publisherKeyHash
        )

        let package = try verifier.verify(fixture.crxData)

        XCTAssertEqual(package.extensionID, fixture.extensionID)
        XCTAssertEqual(package.zipArchiveData, fixture.zipData)
        XCTAssertEqual(
            package.publisherKeyHashHex,
            fixture.publisherKeyHash.hexString
        )
    }

    func testDirectCRXPreparationKeepsTheSignedChromeIdentity()
        async throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-local-crx-import-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = rootURL.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        let archiveURL = rootURL.appending(path: "probe.zip")
        let packageURL = rootURL.appending(path: "probe.crx")
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Local CRX Probe",
                "version": "1.0",
                "permissions": ["storage"],
            ] as [String: Any]
        ).write(to: sourceURL.appending(path: "manifest.json"))
        try createZipArchive(from: sourceURL, at: archiveURL)
        let archiveData = try Data(contentsOf: archiveURL)
        let fixture = try signedFixture(zipData: archiveData)
        try fixture.crxData.write(to: packageURL)

        let candidate = try await BrowserLocalExtensionProvider(
            fileManager: fileManager,
            crxVerifier: BrowserCRX3Verifier(
                requiredPublisherKeyHash: fixture.publisherKeyHash
            ),
            nativeMessagingCapability: .available
        ).candidate(for: packageURL)

        XCTAssertEqual(candidate.id, fixture.extensionID.rawValue)
        XCTAssertEqual(candidate.displayName, "Local CRX Probe")
        XCTAssertEqual(candidate.format, .chromeCRX3)
        XCTAssertEqual(candidate.package.archiveData, archiveData)
        XCTAssertEqual(candidate.requestedPermissions, ["storage"])
        XCTAssertEqual(
            candidate.format.sourceDisplayName,
            "Local Chrome Package"
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

    func testCompatibilityLayerHostsAModuleWorkerInABackgroundDocument()
        throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-compatibility-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let workerURL = root.appending(path: "background/background.js")
        try fileManager.createDirectory(
            at: workerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(to: workerURL)
        let popupURL = root.appending(path: "popup.html")
        try Data(
            """
            <html><head><script src="popup.js"></script></head>
            <body aria-label placeholder="" data-i18n-title='  '>
            <button aria-label="Known message">Open</button>
            </body></html>
            """
            .utf8
        ).write(to: popupURL)
        let appPageURL = root.appending(path: "app/app.html")
        try fileManager.createDirectory(
            at: appPageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<html><body>Settings</body></html>".utf8).write(
            to: appPageURL
        )
        let sandboxPageURL = root.appending(path: "sandbox.html")
        try Data("<html><body>Sandbox</body></html>".utf8).write(
            to: sandboxPageURL
        )
        let contentScriptURL = root.appending(path: "content.js")
        try Data("globalThis.contentStarted = true;".utf8).write(
            to: contentScriptURL
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Compatibility Fixture",
            "version": "1.0",
            "background": [
                "service_worker": "background/background.js",
                "type": "module",
            ],
            "action": ["default_popup": "popup.html"],
            "commands": [
                "_execute_browser_action": [:],
                "open-dashboard": [
                    "description": "Open the dashboard"
                ],
            ],
            "sandbox": ["pages": ["sandbox.html"]],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ]
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
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: ["nativeMessaging", "notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
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
        let backgroundDocumentName = try XCTUnwrap(
            background["page"] as? String
        )
        XCTAssertNil(background["service_worker"])
        XCTAssertNil(background["scripts"])
        XCTAssertNil(background["type"])
        XCTAssertNil(background["preferred_environment"])
        let updatedContentScripts = try XCTUnwrap(
            updated["content_scripts"] as? [[String: Any]]
        )
        let preparedContentScripts = try XCTUnwrap(
            updatedContentScripts.first?["js"] as? [String]
        )
        let compatibilityScriptName = try XCTUnwrap(
            preparedContentScripts.first
        )
        XCTAssertEqual(updated["manifest_version"] as? Int, 3)
        XCTAssertNotNil(updated["action"])
        XCTAssertNil(updated["browser_action"])
        let commands = try XCTUnwrap(
            updated["commands"] as? [String: [String: Any]]
        )
        XCTAssertNil(commands["_execute_action"])
        XCTAssertNil(commands["_execute_browser_action"])
        XCTAssertEqual(
            commands["open-dashboard"]?["description"] as? String,
            "Open the dashboard"
        )
        XCTAssertTrue(
            backgroundDocumentName.hasPrefix(
                "crest-webextension-background-"
            )
        )
        XCTAssertFalse(
            backgroundDocumentName.hasPrefix(
                "crest-webextension-background-bootstrap-"
            )
        )
        XCTAssertTrue(backgroundDocumentName.hasSuffix(".html"))
        XCTAssertTrue(
            compatibilityScriptName.hasPrefix(
                "crest-webextension-compatibility-"
            )
        )
        XCTAssertTrue(compatibilityScriptName.hasSuffix(".js"))
        XCTAssertNil(background["persistent"])
        let preparedWorker = try String(
            contentsOf: workerURL,
            encoding: .utf8
        )
        XCTAssertEqual(preparedWorker, "globalThis.started = true;")

        let backgroundDocument = try String(
            contentsOf: root.appending(
                path: backgroundDocumentName
            ),
            encoding: .utf8
        )
        let compatibilityTag =
            #"<script src="/\#(compatibilityScriptName)"></script>"#
        XCTAssertEqual(
            backgroundDocument.components(
                separatedBy: compatibilityTag
            ).count,
            2,
            "The background document must load the compatibility layer exactly once."
        )
        let workerTag =
            #"<script type="module" src="/background/background.js"></script>"#
        XCTAssertTrue(backgroundDocument.contains(workerTag))
        let compatibilityRange = try XCTUnwrap(
            backgroundDocument.range(of: compatibilityTag)
        )
        let workerRange = try XCTUnwrap(
            backgroundDocument.range(of: workerTag)
        )
        XCTAssertLessThan(
            compatibilityRange.lowerBound,
            workerRange.lowerBound,
            "The compatibility layer must load before the worker module."
        )
        XCTAssertFalse(backgroundDocument.contains("__crest"))

        let compatibilityScript = try String(
            contentsOf: root.appending(
                path: compatibilityScriptName
            ),
            encoding: .utf8
        )
        let compatibilityFingerprint = Data(
            SHA256.hash(data: Data(compatibilityScript.utf8)).prefix(8)
        ).hexString
        XCTAssertEqual(
            compatibilityScriptName,
            "crest-webextension-compatibility-\(compatibilityFingerprint).js"
        )
        let backgroundDocumentFingerprint = Data(
            SHA256.hash(data: Data(backgroundDocument.utf8)).prefix(8)
        ).hexString
        XCTAssertEqual(
            backgroundDocumentName,
            "crest-webextension-background-\(backgroundDocumentFingerprint).html"
        )
        for requiredSurface in [
            "notifications",
            "onCreatedNavigationTarget",
            "getUserSettings",
            "addHostAccessRequest",
            "passwordSavingEnabled",
            "storageManaged",
            "onChanged",
            "installFallbacks",
            "namespaceFacade",
            "installNamespaceFacades",
            "installNativeAliases",
            "installMissingRoot",
            "get() { return facade; }",
            "serviceWorkerClients",
            "skipWaiting",
            "offscreen",
            "management",
            "downloads",
            "idle",
            "requestIdleCallback",
            "onAuthRequired",
            "handlerBehaviorChanged",
            "requestUpdateCheck",
            "onUpdateAvailable",
            "normalizeMenuNamespace",
            "wrappedJSObject",
        ] {
            XCTAssertTrue(
                compatibilityScript.contains(requiredSurface),
                "Missing compatibility surface: \(requiredSurface)"
            )
        }
        XCTAssertTrue(compatibilityScript.contains("declaredManifest"))
        XCTAssertTrue(compatibilityScript.contains("options?.url"))
        XCTAssertFalse(
            compatibilityScript.contains(
                "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
            )
        )
        XCTAssertFalse(
            compatibilityScript.contains(
                "background/offscreen/offscreen.js"
            )
        )

        let preparedPopup = try String(contentsOf: popupURL, encoding: .utf8)
        XCTAssertTrue(
            preparedPopup.contains(
                #"src="/\#(compatibilityScriptName)""#
            )
        )
        XCTAssertFalse(preparedPopup.contains("<body aria-label"))
        XCTAssertFalse(preparedPopup.contains("placeholder=\"\""))
        XCTAssertFalse(preparedPopup.contains("data-i18n-title='  '"))
        XCTAssertTrue(
            preparedPopup.contains(#"aria-label="Known message""#)
        )
        let preparedAppPage = try String(
            contentsOf: appPageURL,
            encoding: .utf8
        )
        XCTAssertTrue(
            preparedAppPage.contains(
                #"src="/\#(compatibilityScriptName)""#
            )
        )
        let preparedSandboxPage = try String(
            contentsOf: sandboxPageURL,
            encoding: .utf8
        )
        XCTAssertFalse(
            preparedSandboxPage.contains(
                #"src="/\#(compatibilityScriptName)""#
            )
        )
        XCTAssertEqual(
            preparedContentScripts,
            [compatibilityScriptName, "content.js"]
        )
    }

    func testCompatibilityLayerKeepsAClassicWorkerBehindItsBootstrap() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-classic-worker-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("importScripts('helper.js');".utf8).write(
            to: root.appending(path: "background.js")
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Classic Worker Fixture",
            "version": "1.0",
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
                requestedPermissions: ["notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )

        let updated = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appending(path: "manifest.json"))
            ) as? [String: Any]
        )
        let background = try XCTUnwrap(
            updated["background"] as? [String: Any]
        )
        let bootstrapName = try XCTUnwrap(
            background["service_worker"] as? String
        )
        XCTAssertTrue(
            bootstrapName.hasPrefix(
                "crest-webextension-background-bootstrap-"
            )
        )
        XCTAssertNil(background["scripts"])
        XCTAssertNil(background["page"])
        let bootstrapScript = try String(
            contentsOf: root.appending(path: bootstrapName),
            encoding: .utf8
        )
        XCTAssertTrue(bootstrapScript.hasPrefix("importScripts("))
        XCTAssertTrue(bootstrapScript.contains(#""./background.js""#))
    }

    func testCompatibilityLayerPrefersDocumentScriptsOverAClassicWorker()
        throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-dual-background-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Dual Background Fixture",
            "version": "1.0",
            "background": [
                "service_worker": "background.js",
                "scripts": ["background.js"],
                "preferred_environment": "service_worker",
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
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: ["notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )

        let updated = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appending(path: "manifest.json"))
            ) as? [String: Any]
        )
        let background = try XCTUnwrap(
            updated["background"] as? [String: Any]
        )
        let scripts = try XCTUnwrap(background["scripts"] as? [String])
        XCTAssertEqual(scripts.count, 2)
        XCTAssertEqual(scripts.last, "background.js")
        XCTAssertTrue(
            try XCTUnwrap(scripts.first).hasPrefix(
                "crest-webextension-compatibility-"
            )
        )
        XCTAssertNil(background["service_worker"])
        XCTAssertNil(background["preferred_environment"])
    }

    func testCompatibilityLayerRemovesALegacyCrestWorkerPrelude() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-legacy-prelude-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let workerURL = root.appending(path: "background.js")
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let originalWorker = "globalThis.originalWorker = true;\n"
        let legacyWorker =
            """
            // Crest's WKWebExtension host currently has no notifications API.
            const crestNoopEvent = Object.freeze({});
            const crestChromeCompatibility = {};
            Object.defineProperty(globalThis, "chrome", {
                value: crestChromeCompatibility,
                configurable: true
            });
            }


            \(originalWorker)
            """
        try Data(legacyWorker.utf8).write(to: workerURL)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "background": [
                "service_worker": "background.js",
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
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: ["notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )

        XCTAssertEqual(
            try String(contentsOf: workerURL, encoding: .utf8),
            originalWorker
        )
    }

    func testGeneratedCompatibilityRuntimeParsesInWebKit() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-runtime-parse-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Runtime Parse Fixture",
            "version": "1.0",
            "background": ["scripts": ["background.js"]],
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
                requestedPermissions: ["notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )

        _ = try await WKWebView().evaluateJavaScript(source)
    }

    func testManifestDiagnosticsHideOnlyTheValidEmptyActionCommandWarning()
        async throws
    {
        let fileManager = FileManager.default
        for (commandName, shouldExposeWarning) in [
            ("_execute_action", false),
            ("save-page", true),
        ] {
            let root = fileManager.temporaryDirectory.appending(
                path:
                    "crest-webextension-command-diagnostic-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
            defer { try? fileManager.removeItem(at: root) }
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            try JSONSerialization.data(
                withJSONObject: [
                    "manifest_version": 3,
                    "name": "Command Diagnostic Fixture",
                    "version": "1.0",
                    "commands": [commandName: [:]],
                ] as [String: Any]
            ).write(to: root.appending(path: "manifest.json"))

            let webExtension = try await WKWebExtension(
                resourceBaseURL: root
            )
            let rawWarnings = webExtension.errors.map(
                \.localizedDescription
            )
            let displayedWarnings =
                BrowserWebExtensionManifestCompatibilityPolicy
                .displayErrors(for: webExtension)
            let rawHasCommandWarning = rawWarnings.contains { warning in
                warning.lowercased().contains("empty or invalid command")
            }
            let displayedHasCommandWarning = displayedWarnings.contains {
                warning in
                warning.lowercased().contains("empty or invalid command")
            }

            XCTAssertTrue(rawHasCommandWarning)
            XCTAssertEqual(
                displayedHasCommandWarning,
                shouldExposeWarning,
                "Only the reserved empty action command is valid."
            )
        }
    }

    func testPermissionsCompatibilitySettlesMissingNativeRepliesAndProtectsRequiredAccess()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-permissions-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Permissions Fixture",
            "version": "1.0",
            "permissions": ["contextMenus", "storage"],
            "host_permissions": ["*://api.example.test/*"],
            "optional_permissions": ["tabs"],
            "optional_host_permissions": ["*://*/*"],
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["contextMenus", "storage"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            let nativeContainsCalls = 0;
            let nativeRemoveCalls = 0;
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; }
                    },
                    permissions: {
                        contains() {
                            nativeContainsCalls += 1;
                            return new Promise(() => {});
                        },
                        remove() {
                            nativeRemoveCalls += 1;
                            return new Promise(() => {});
                        }
                    }
                }
            });
            \(source)
            let callbackContains;
            const callbackFinished = new Promise((resolve) => {
                browser.permissions.contains(
                    { origins: ["http://a.example/"] },
                    (value) => {
                        callbackContains = value;
                        resolve();
                    }
                );
            });
            const promiseContains = browser.permissions.contains({
                permissions: ["tabs"],
                origins: ["*://*/*"]
            });
            await callbackFinished;
            const optionalContains = await promiseContains;
            const optionalRemoved = await browser.permissions.remove({
                permissions: ["tabs"],
                origins: ["*://*/*"]
            });
            const requiredRemoved = await browser.permissions.remove({
                origins: ["*://api.example.test/*"]
            });
            return JSON.stringify({
                callbackContains,
                optionalContains,
                optionalRemoved,
                requiredRemoved,
                nativeContainsCalls,
                nativeRemoveCalls
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(result["callbackContains"] as? Bool, false)
        XCTAssertEqual(result["optionalContains"] as? Bool, false)
        XCTAssertEqual(result["optionalRemoved"] as? Bool, false)
        XCTAssertEqual(result["requiredRemoved"] as? Bool, false)
        XCTAssertEqual(result["nativeContainsCalls"] as? Int, 3)
        XCTAssertEqual(result["nativeRemoveCalls"] as? Int, 0)
    }

    func testPrivacySettingsReportEffectiveUncontrollableValuesWithoutRejecting()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-privacy-settings-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Privacy Settings Fixture",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["privacy"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let webView = WKWebView()
        let evaluatedResult = try await webView.callAsyncJavaScript(
            """
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; }
                    }
                }
            });
            \(source)
            try {
                const passwords = await browser.privacy.services
                    .passwordSavingEnabled.get({});
                await browser.privacy.services.passwordSavingEnabled.set({
                    value: false
                });
                await browser.privacy.services.passwordSavingEnabled.clear({});
                const passwordsAfterSet = await browser.privacy.services
                    .passwordSavingEnabled.get({});
                const cards = await browser.privacy.services
                    .autofillCreditCardEnabled.get({});
                const addresses = await browser.privacy.services
                    .autofillAddressEnabled.get({});
                const autofill = await browser.privacy.services
                    .autofillEnabled.get({});
                await browser.privacy.services.autofillEnabled.set({
                    value: false
                });
                await browser.privacy.services.autofillEnabled.clear({});
                return JSON.stringify({
                    settled: true,
                    passwords,
                    passwordsAfterSet,
                    cards,
                    addresses,
                    autofill
                });
            } catch (error) {
                return JSON.stringify({
                    settled: true,
                    error: error?.message ?? String(error)
                });
            }
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(result["settled"] as? Bool, true)
        XCTAssertNil(result["error"])
        for key in ["passwords", "passwordsAfterSet"] {
            let setting = try XCTUnwrap(result[key] as? [String: Any])
            XCTAssertEqual(setting["value"] as? Bool, true)
            XCTAssertEqual(
                setting["levelOfControl"] as? String,
                "not_controllable"
            )
        }
        for key in ["cards", "addresses", "autofill"] {
            let setting = try XCTUnwrap(result[key] as? [String: Any])
            XCTAssertEqual(setting["value"] as? Bool, false)
            XCTAssertEqual(
                setting["levelOfControl"] as? String,
                "not_controllable"
            )
        }
    }

    func testNotificationsUseTheCrestCapabilityBroker() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-notifications-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Notifications Fixture",
            "version": "1.0",
            "permissions": ["nativeMessaging", "notifications"],
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["nativeMessaging", "notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            const requests = [];
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; },
                        async sendNativeMessage(host, message) {
                            requests.push({ host, message });
                            switch (message.api) {
                            case "notifications.create":
                                return {
                                    notificationIdentifier:
                                        message.notificationIdentifier,
                                    presented: true
                                };
                            case "notifications.getAll":
                                return { notificationIdentifiers: ["saved"] };
                            case "notifications.update":
                                return { updated: true };
                            case "notifications.clear":
                                return { cleared: true };
                            case "notifications.getPermissionLevel":
                                return { level: "granted" };
                            default:
                                throw new Error(`Unexpected ${message.api}`);
                            }
                        }
                    }
                }
            });
            \(source)
            const created = await browser.notifications.create("saved", {
                type: "basic",
                title: "Saved",
                message: "The login was saved.",
                buttons: [{ title: "Open" }]
            });
            const all = await browser.notifications.getAll();
            const updated = await browser.notifications.update("saved", {
                type: "basic",
                title: "Updated",
                message: "The saved login changed.",
                buttons: [{ title: "Review" }]
            });
            const cleared = await browser.notifications.clear("saved");
            const permission = await browser.notifications
                .getPermissionLevel();
            return JSON.stringify({
                created,
                all,
                updated,
                cleared,
                permission,
                requests
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(result["created"] as? String, "saved")
        XCTAssertEqual(
            result["all"] as? [String: Bool],
            ["saved": true]
        )
        XCTAssertEqual(result["updated"] as? Bool, true)
        XCTAssertEqual(result["cleared"] as? Bool, true)
        XCTAssertEqual(result["permission"] as? String, "granted")
        let requests = try XCTUnwrap(
            result["requests"] as? [[String: Any]]
        )
        XCTAssertEqual(
            requests.compactMap { request in
                (request["message"] as? [String: Any])?["api"] as? String
            },
            [
                "notifications.create",
                "notifications.getAll",
                "notifications.update",
                "notifications.clear",
                "notifications.getPermissionLevel",
            ]
        )
        let createRequest = try XCTUnwrap(
            requests.first?["message"] as? [String: Any]
        )
        XCTAssertEqual(
            createRequest["notificationIdentifier"] as? String,
            "saved"
        )
        XCTAssertEqual(createRequest["title"] as? String, "Saved")
        XCTAssertEqual(
            createRequest["message"] as? String,
            "The login was saved."
        )
        XCTAssertEqual(
            createRequest["buttonTitles"] as? [String],
            ["Open"]
        )
        let updateRequest = try XCTUnwrap(
            requests[2]["message"] as? [String: Any]
        )
        XCTAssertEqual(
            updateRequest["notificationIdentifier"] as? String,
            "saved"
        )
        XCTAssertEqual(updateRequest["title"] as? String, "Updated")
        XCTAssertEqual(
            updateRequest["message"] as? String,
            "The saved login changed."
        )
        XCTAssertEqual(
            updateRequest["buttonTitles"] as? [String],
            ["Review"]
        )
    }

    func testNotificationEventsUseTheCrestCapabilityBrokerPort()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-notification-events-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Notification Events Fixture",
            "version": "1.0",
            "permissions": ["nativeMessaging", "notifications"],
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["nativeMessaging", "notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            let receivedHost;
            let receivedConfiguration;
            let disconnectCount = 0;
            const messageListeners = [];
            const port = {
                onMessage: {
                    addListener(listener) { messageListeners.push(listener); }
                },
                onDisconnect: { addListener() {} },
                postMessage(message) { receivedConfiguration = message; },
                disconnect() { disconnectCount += 1; }
            };
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; },
                        connectNative(host) {
                            receivedHost = host;
                            return port;
                        }
                    }
                }
            });
            \(source)
            const clicked = [];
            const buttonClicked = [];
            const closed = [];
            const clickedListener = (identifier) => clicked.push(identifier);
            const buttonListener = (identifier, index) =>
                buttonClicked.push([identifier, index]);
            const closedListener = (identifier, byUser) =>
                closed.push([identifier, byUser]);
            browser.notifications.onClicked.addListener(clickedListener);
            browser.notifications.onButtonClicked.addListener(buttonListener);
            browser.notifications.onClosed.addListener(closedListener);
            messageListeners[0]?.({
                api: "notifications.event",
                kind: "clicked",
                notificationIdentifier: "saved"
            });
            messageListeners[0]?.({
                api: "notifications.event",
                kind: "buttonClicked",
                notificationIdentifier: "saved",
                buttonIndex: 1
            });
            messageListeners[0]?.({
                api: "notifications.event",
                kind: "closed",
                notificationIdentifier: "saved",
                byUser: true
            });
            const hadClickedListener = browser.notifications.onClicked
                .hasListener(clickedListener);
            browser.notifications.onClicked.removeListener(clickedListener);
            browser.notifications.onButtonClicked.removeListener(
                buttonListener
            );
            browser.notifications.onClosed.removeListener(closedListener);
            return JSON.stringify({
                receivedHost,
                receivedConfiguration,
                clicked,
                buttonClicked,
                closed,
                hadClickedListener,
                disconnectCount,
                messageListenerCount: messageListeners.length
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(
            result["receivedHost"] as? String,
            "com.pauldavis.crest.webextension-compatibility"
        )
        XCTAssertEqual(
            (result["receivedConfiguration"] as? [String: Any])?["api"]
                as? String,
            "notifications.watch"
        )
        XCTAssertEqual(result["clicked"] as? [String], ["saved"])
        XCTAssertEqual(
            result["buttonClicked"] as? [[AnyHashable]],
            [["saved", 1]]
        )
        XCTAssertEqual(
            result["closed"] as? [[AnyHashable]],
            [["saved", true]]
        )
        XCTAssertEqual(result["hadClickedListener"] as? Bool, true)
        XCTAssertEqual(result["disconnectCount"] as? Int, 1)
        XCTAssertEqual(result["messageListenerCount"] as? Int, 1)
    }

    func testIdleStateUsesTheCrestCapabilityBroker() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-idle-state-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Idle State Fixture",
            "version": "1.0",
            "permissions": ["idle", "nativeMessaging"],
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["idle", "nativeMessaging"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            let receivedHost;
            let receivedMessage;
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; },
                        sendNativeMessage(host, message) {
                            if (arguments.length !== 2) {
                                throw new Error(
                                    "Promise-style native messaging accepts two arguments."
                                );
                            }
                            receivedHost = host;
                            receivedMessage = message;
                            return Promise.resolve({ state: "active" });
                        }
                    }
                }
            });
            \(source)
            const state = await browser.idle.queryState(300);
            return JSON.stringify({
                state,
                receivedHost,
                receivedMessage
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(result["state"] as? String, "active")
        XCTAssertEqual(
            result["receivedHost"] as? String,
            "com.pauldavis.crest.webextension-compatibility"
        )
        let receivedMessage = try XCTUnwrap(
            result["receivedMessage"] as? [String: Any]
        )
        XCTAssertEqual(receivedMessage["api"] as? String, "idle.queryState")
        XCTAssertEqual(
            receivedMessage["detectionIntervalInSeconds"] as? Int,
            300
        )
    }

    func testIdleStateChangeUsesTheCrestCapabilityBrokerPort() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-idle-event-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Idle Event Fixture",
            "version": "1.0",
            "permissions": ["idle", "nativeMessaging"],
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["idle", "nativeMessaging"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            let receivedHost;
            let receivedConfiguration;
            const messageListeners = [];
            const disconnectListeners = [];
            const port = {
                onMessage: {
                    addListener(listener) { messageListeners.push(listener); },
                    removeListener(listener) {
                        const index = messageListeners.indexOf(listener);
                        if (index >= 0) messageListeners.splice(index, 1);
                    }
                },
                onDisconnect: {
                    addListener(listener) {
                        disconnectListeners.push(listener);
                    }
                },
                postMessage(message) { receivedConfiguration = message; },
                disconnect() {}
            };
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; },
                        connectNative(host) {
                            receivedHost = host;
                            return port;
                        }
                    }
                }
            });
            \(source)
            let observedState;
            browser.idle.onStateChanged.addListener((state) => {
                observedState = state;
            });
            browser.idle.setDetectionInterval(45);
            messageListeners[0]?.({ state: "idle" });
            return JSON.stringify({
                receivedHost,
                receivedConfiguration,
                observedState,
                messageListenerCount: messageListeners.length
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(
            result["receivedHost"] as? String,
            "com.pauldavis.crest.webextension-compatibility"
        )
        let configuration = try XCTUnwrap(
            result["receivedConfiguration"] as? [String: Any]
        )
        XCTAssertEqual(configuration["api"] as? String, "idle.watch")
        XCTAssertEqual(
            configuration["detectionIntervalInSeconds"] as? Int,
            45
        )
        XCTAssertEqual(result["observedState"] as? String, "idle")
        XCTAssertEqual(result["messageListenerCount"] as? Int, 1)
    }

    func testGeneratedCompatibilityRuntimeSuppliesStableRuntimeIdentityAndURLs()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-runtime-identity-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Runtime Identity Fixture",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "manifest.json")
        )
        let runtimeIdentity = BrowserExtensionRuntimeIdentity(
            extensionID: "fixture-extension-id",
            uniqueIdentifier: "fixture-extension-id.space.personal",
            baseURL: try XCTUnwrap(
                URL(string: "crest-extension://fixture-runtime/")
            )
        )
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )
        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: ["nativeMessaging", "notifications"],
                runtimeIdentity: runtimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            const nativeRuntime = {
                getManifest() { return { manifest_version: 3 }; },
                getURL(path = "") {
                    if (this !== nativeRuntime) return undefined;
                    return new URL(
                        String(path),
                        "crest-extension://fixture-runtime/"
                    ).href;
                },
                sendMessage() {},
                connectNative() {
                    return this === nativeRuntime
                        ? { receiver: "native" }
                        : undefined;
                }
            };
            const nativeI18n = Object.freeze({
                getMessage(name) {
                    if (name === "") {
                        throw new Error("An empty message name is invalid");
                    }
                    return this === nativeI18n ? `native:${name}` : undefined;
                }
            });
            const nativeCommittedEvent = Object.freeze({
                receiver: "native-event"
            });
            const nativeWebNavigation = Object.preventExtensions({
                onCommitted: nativeCommittedEvent,
                getFrame() {
                    return this === nativeWebNavigation
                        ? { receiver: "native-namespace" }
                        : undefined;
                }
            });
            const nativeRequestEvent = Object.freeze({
                receiver: "native-request-event"
            });
            const nativeWebRequest = Object.preventExtensions({
                onBeforeRequest: nativeRequestEvent
            });
            const createdMenus = [];
            const nativeMenus = Object.freeze({
                create(properties) {
                    createdMenus.push(properties);
                    return properties.id;
                }
            });
            const nativeRoot = {
                runtime: nativeRuntime,
                menus: nativeMenus,
                webNavigation: nativeWebNavigation,
                webRequest: nativeWebRequest
            };
            Object.defineProperty(nativeRoot, "i18n", {
                configurable: false,
                value: nativeI18n
            });
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: nativeRoot
            });
            \(source)
            const detachedGetURL = browser.runtime.getURL;
            const detachedGetMessage = browser.i18n.getMessage;
            const menuID = browser.menus.create({
                id: "subscribe",
                targetUrlPatterns: [
                    "abp:*",
                    "https://subscribe.example/*"
                ]
            });
            let cancelledIdleCallbackRan = false;
            const cancelledIdleCallback = requestIdleCallback(() => {
                cancelledIdleCallbackRan = true;
            });
            cancelIdleCallback(cancelledIdleCallback);
            await new Promise((resolve) => setTimeout(resolve, 10));
            const idleDeadline = await new Promise((resolve) => {
                requestIdleCallback(resolve);
            });
            await browser.webRequest.handlerBehaviorChanged();
            return JSON.stringify({
                id: chrome.runtime.id,
                root: chrome.runtime.getURL(""),
                resource: chrome.runtime.getURL("images/icon.png"),
                detachedRoot: detachedGetURL(""),
                emptyMessage: detachedGetMessage(""),
                translatedMessage: detachedGetMessage("known"),
                sameRoot: chrome === browser,
                sameRuntime: chrome.runtime === nativeRuntime,
                sameI18n: chrome.i18n === nativeI18n,
                manifestWorker:
                    chrome.runtime.getManifest().background?.service_worker,
                cancelledIdleCallbackRan,
                idleDidTimeout: idleDeadline.didTimeout,
                idleTimeRemaining: idleDeadline.timeRemaining(),
                sameCommittedEvent:
                    chrome.webNavigation.onCommitted
                        === nativeCommittedEvent,
                sameRequestEvent:
                    chrome.webRequest.onBeforeRequest
                        === nativeRequestEvent,
                handlerBehaviorChanged:
                    typeof chrome.webRequest.handlerBehaviorChanged,
                nativeNamespaceReceiver:
                    chrome.webNavigation.getFrame()?.receiver,
                addedNavigationEvent:
                    typeof chrome.webNavigation
                        .onCreatedNavigationTarget?.addListener,
                enumerableNavigationEvent:
                    Object.keys(chrome.webNavigation)
                        .includes("onCreatedNavigationTarget"),
                nativeReceiver:
                    browser.runtime.connectNative("")?.receiver,
                updateAvailableEvent:
                    typeof browser.runtime.onUpdateAvailable?.addListener,
                menuID,
                menuContexts: createdMenus[0]?.contexts,
                menuTargetPatterns: createdMenus[0]?.targetUrlPatterns,
                wrappedJSObjectType: typeof globalThis.wrappedJSObject,
                wrappedSentinel: globalThis.wrappedJSObject?.crestSentinel
            })
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(result["id"] as? String, runtimeIdentity.extensionID)
        XCTAssertEqual(
            result["root"] as? String,
            runtimeIdentity.baseURL.absoluteString
        )
        XCTAssertEqual(
            result["resource"] as? String,
            runtimeIdentity.baseURL.appending(
                path: "images/icon.png"
            ).absoluteString
        )
        XCTAssertEqual(
            result["detachedRoot"] as? String,
            runtimeIdentity.baseURL.absoluteString
        )
        XCTAssertEqual(result["emptyMessage"] as? String, "")
        XCTAssertEqual(result["translatedMessage"] as? String, "native:known")
        XCTAssertEqual(result["sameRoot"] as? Bool, true)
        XCTAssertEqual(result["sameRuntime"] as? Bool, true)
        XCTAssertEqual(result["sameI18n"] as? Bool, false)
        XCTAssertEqual(
            result["manifestWorker"] as? String,
            "background.js"
        )
        XCTAssertEqual(result["cancelledIdleCallbackRan"] as? Bool, false)
        XCTAssertEqual(result["idleDidTimeout"] as? Bool, false)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(result["idleTimeRemaining"] as? Double),
            0
        )
        XCTAssertEqual(result["sameCommittedEvent"] as? Bool, true)
        XCTAssertEqual(result["sameRequestEvent"] as? Bool, true)
        XCTAssertEqual(
            result["handlerBehaviorChanged"] as? String,
            "function"
        )
        XCTAssertEqual(
            result["nativeNamespaceReceiver"] as? String,
            "native-namespace"
        )
        XCTAssertEqual(result["addedNavigationEvent"] as? String, "function")
        XCTAssertEqual(result["enumerableNavigationEvent"] as? Bool, true)
        XCTAssertEqual(result["nativeReceiver"] as? String, "native")
        XCTAssertEqual(result["updateAvailableEvent"] as? String, "function")
        XCTAssertEqual(result["menuID"] as? String, "subscribe")
        XCTAssertEqual(result["menuContexts"] as? [String], ["tab"])
        XCTAssertEqual(
            result["menuTargetPatterns"] as? [String],
            []
        )
        XCTAssertEqual(result["wrappedJSObjectType"] as? String, "object")
        XCTAssertNil(result["wrappedSentinel"])
    }

    func testCompatibilityRuntimeTransportsWebpageMenuDefinitionsAndEnrichesNativeClicks()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-context-menu-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Context Menu Transport Fixture",
            "version": "1.0",
            "permissions": ["contextMenus", "sidePanel"],
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "manifest.json")
        )
        let runtimeIdentity = BrowserExtensionRuntimeIdentity(
            extensionID: "context-menu-fixture",
            uniqueIdentifier: "context-menu-fixture.space.personal",
            baseURL: try XCTUnwrap(
                URL(string: "crest-extension://context-menu-fixture/")
            )
        )
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )
        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: ["contextMenus", "sidePanel"],
                runtimeIdentity: runtimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let contextMenusTransportWebView = WKWebView()
        let evaluatedResult =
            try await contextMenusTransportWebView
            .callAsyncJavaScript(
                """
                return await (async () => {
                try {
                const nativeCreates = [];
                const brokerMessages = [];
                let brokerHost;
                let brokerMessageListener;
                let nativeClickListener;
                let nativeInstalledListener;
                const port = {
                    postMessage(message) { brokerMessages.push(message); },
                    onMessage: {
                        addListener(listener) { brokerMessageListener = listener; }
                    },
                    onDisconnect: { addListener() {} }
                };
                const nativeRuntime = {
                    getManifest() { return { manifest_version: 3 }; },
                    getURL(path = "") {
                        return new URL(
                            String(path),
                            "crest-extension://context-menu-fixture/"
                        ).href;
                    },
                    connectNative(host) {
                        brokerHost = host;
                        return port;
                    }
                };
                Object.defineProperty(nativeRuntime, "onInstalled", {
                    configurable: false,
                    writable: false,
                    enumerable: true,
                    value: {
                        addListener(listener) {
                            nativeInstalledListener = listener;
                        }
                    }
                });
                const nativeMenus = {
                    create(properties) {
                        nativeCreates.push(properties);
                        return properties.id;
                    },
                    update() {},
                    remove() {},
                    removeAll(callback) { callback?.(); }
                };
                Object.defineProperty(nativeMenus, "onClicked", {
                    configurable: false,
                    writable: false,
                    enumerable: true,
                    value: {
                        addListener(listener) { nativeClickListener = listener; }
                    }
                });
                const nativeChrome = {
                    runtime: nativeRuntime,
                    menus: nativeMenus
                };
                Object.defineProperty(nativeChrome, "contextMenus", {
                    configurable: false,
                    writable: false,
                    enumerable: true,
                    value: nativeMenus
                });
                Object.defineProperty(globalThis, "chrome", {
                    configurable: false,
                    writable: false,
                    value: nativeChrome
                });
                \(source)
                let sidePanelError;
                try {
                    await chrome.sidePanel.setPanelBehavior({
                        openPanelOnActionClick: true
                    });
                } catch (error) {
                    sidePanelError = String(error);
                }
                brokerMessageListener?.({
                    api: "runtime.onInstalled",
                    eventID: "fresh-install-event",
                    reason: "install"
                });
                const callbackClicks = [];
                const eventClicks = [];
                const chromeEventClicks = [];
                const installedReasons = [];
                chrome.runtime.onInstalled.addListener((details) => {
                    installedReasons.push(details.reason);
                });
                browser.contextMenus.onClicked.addListener((info, tab) => {
                    eventClicks.push({ info, tab });
                });
                chrome.contextMenus.onClicked.addListener((info, tab) => {
                    chromeEventClicks.push({ info, tab });
                });
                brokerMessageListener?.({
                    api: "contextMenus.click",
                    menuItemID: "string:restored",
                    pageURL: "https://page.example/article",
                    documentURL: "https://page.example/article",
                    sourceURL: "https://cdn.example/restored.webp",
                    mediaType: "image",
                    editable: false,
                    mainFrame: true
                });
                nativeClickListener?.(
                    { menuItemId: "string:restored", frameId: 0 },
                    { id: 7, url: "https://page.example/article" }
                );
                brokerMessageListener?.({
                    api: "contextMenus.restore",
                    items: [{
                        id: "string:restored",
                        type: "normal",
                        title: "Restored Image",
                        contexts: ["image"],
                        documentUrlPatterns: ["https://page.example/*"],
                        targetUrlPatterns: ["https://cdn.example/*.webp"],
                        enabled: true,
                        visible: true
                    }]
                });
                browser.contextMenus.create({
                    id: "image",
                    title: "Convert %s",
                    contexts: ["image"],
                    documentUrlPatterns: ["https://page.example/*"],
                    targetUrlPatterns: ["https://cdn.example/*.webp"],
                    onclick(info, tab) {
                        callbackClicks.push({ info, tab });
                    }
                });
                brokerMessageListener?.({
                    api: "contextMenus.click",
                    menuItemID: "string:image",
                    pageURL: "https://page.example/article",
                    documentURL: "https://frame.example/content",
                    sourceURL: "https://cdn.example/photo.webp",
                    selectionText: "photo",
                    editable: false,
                    mainFrame: false
                });
                nativeClickListener?.(
                    {
                        menuItemId: "string:image",
                        frameId: 99,
                        wasChecked: false
                    },
                    { id: 7, url: "https://page.example/article" }
                );
                browser.contextMenus.create({
                    id: "tab",
                    title: "Tab Action",
                    contexts: ["tab"]
                });
                nativeClickListener?.(
                    {
                        menuItemId: "string:tab",
                        pageUrl: "https://page.example/article"
                    },
                    { id: 7, url: "https://page.example/article" }
                );
                await new Promise((resolve) => setTimeout(resolve, 100));
                return JSON.stringify({
                    brokerHost,
                    nativeCreate: nativeCreates[0],
                    definition:
                        brokerMessages[brokerMessages.length - 1]?.items,
                    callbackClick: callbackClicks[0],
                    restoredClick: eventClicks[0],
                    eventClick: eventClicks[1],
                    chromeEventClick: chromeEventClicks[1],
                    installedReasons,
                    brokerAPIs: brokerMessages.map((message) => message.api),
                    sidePanelError,
                    tabClick: eventClicks[2]
                });
                } catch (error) {
                    return JSON.stringify({
                        scriptError: String(error),
                        scriptStack: String(error?.stack ?? "")
                    });
                }
                })();
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
        withExtendedLifetime(contextMenusTransportWebView) {}
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )
        if let scriptError = result["scriptError"] as? String {
            XCTFail(
                "Compatibility context-menu script failed: \(scriptError)\n\(result["scriptStack"] as? String ?? "")"
            )
            return
        }
        XCTAssertEqual(
            result["brokerHost"] as? String,
            BrowserNativeMessagingService.capabilityBrokerIdentifier
        )
        XCTAssertEqual(
            result["installedReasons"] as? [String],
            ["install"],
            "\(result)"
        )
        let brokerAPIs = try XCTUnwrap(result["brokerAPIs"] as? [String])
        XCTAssertTrue(brokerAPIs.contains("contextMenus.ready"))
        XCTAssertTrue(brokerAPIs.contains("runtime.onInstalled.ack"))
        XCTAssertEqual(
            result["sidePanelError"] as? String,
            "Error: Side panels are not available in Crest."
        )
        let nativeCreate = try XCTUnwrap(
            result["nativeCreate"] as? [String: Any]
        )
        XCTAssertEqual(nativeCreate["id"] as? String, "string:image")
        XCTAssertEqual(nativeCreate["contexts"] as? [String], ["tab"])
        XCTAssertEqual(nativeCreate["documentUrlPatterns"] as? [String], [])
        XCTAssertEqual(nativeCreate["targetUrlPatterns"] as? [String], [])
        XCTAssertEqual(nativeCreate["visible"] as? Bool, true)
        let definitions = try XCTUnwrap(
            result["definition"] as? [[String: Any]]
        )
        let definition = try XCTUnwrap(
            definitions.first { $0["id"] as? String == "string:image" }
        )
        XCTAssertEqual(definition["id"] as? String, "string:image")
        XCTAssertEqual(definition["contexts"] as? [String], ["image"])
        XCTAssertEqual(
            definition["documentUrlPatterns"] as? [String],
            ["https://page.example/*"]
        )
        XCTAssertEqual(
            definition["targetUrlPatterns"] as? [String],
            ["https://cdn.example/*.webp"]
        )
        let restoredClick = try XCTUnwrap(
            result["restoredClick"] as? [String: Any]
        )
        let restoredInfo = try XCTUnwrap(
            restoredClick["info"] as? [String: Any]
        )
        XCTAssertEqual(restoredInfo["menuItemId"] as? String, "restored")
        XCTAssertEqual(
            restoredInfo["srcUrl"] as? String,
            "https://cdn.example/restored.webp"
        )
        XCTAssertEqual(restoredInfo["mediaType"] as? String, "image")
        XCTAssertEqual(restoredInfo["frameId"] as? Int, 0)
        for key in ["callbackClick", "eventClick", "chromeEventClick"] {
            let click = try XCTUnwrap(result[key] as? [String: Any])
            let info = try XCTUnwrap(click["info"] as? [String: Any])
            let tab = try XCTUnwrap(click["tab"] as? [String: Any])
            XCTAssertEqual(info["menuItemId"] as? String, "image")
            XCTAssertEqual(
                info["pageUrl"] as? String,
                "https://page.example/article"
            )
            XCTAssertEqual(
                info["frameUrl"] as? String,
                "https://frame.example/content"
            )
            XCTAssertEqual(
                info["srcUrl"] as? String,
                "https://cdn.example/photo.webp"
            )
            XCTAssertEqual(info["selectionText"] as? String, "photo")
            XCTAssertEqual(info["editable"] as? Bool, false)
            XCTAssertNil(info["frameId"])
            XCTAssertEqual(info["wasChecked"] as? Bool, false)
            XCTAssertEqual(tab["id"] as? Int, 7)
        }
        let tabClick = try XCTUnwrap(
            result["tabClick"] as? [String: Any]
        )
        let tabInfo = try XCTUnwrap(
            tabClick["info"] as? [String: Any]
        )
        XCTAssertEqual(tabInfo["menuItemId"] as? String, "tab")
        XCTAssertEqual(
            tabInfo["pageUrl"] as? String,
            "https://page.example/article"
        )
    }

    func testCompatibilityFacadeSurvivesNativeNamespaceRefresh() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-namespace-refresh-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Namespace Refresh Fixture",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
        ]
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
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
                requestedPermissions: ["webNavigation"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            const nativeCommittedEvent = { receiver: "native-event" };
            const nativeWebNavigation = {
                onCommitted: nativeCommittedEvent
            };
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; }
                    },
                    webNavigation: nativeWebNavigation
                }
            });
            \(source)
            const installedBeforeRefresh =
                typeof chrome.webNavigation
                    .onCreatedNavigationTarget?.addListener;
            Reflect.deleteProperty(
                nativeWebNavigation,
                "onCreatedNavigationTarget"
            );
            return JSON.stringify({
                installedBeforeRefresh,
                installedAfterRefresh:
                    typeof chrome.webNavigation
                        .onCreatedNavigationTarget?.addListener,
                preservedNativeEvent:
                    chrome.webNavigation.onCommitted
                        === nativeCommittedEvent
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let resultJSON = try XCTUnwrap(evaluatedResult as? String)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSON.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(result["installedBeforeRefresh"] as? String, "function")
        XCTAssertEqual(result["installedAfterRefresh"] as? String, "function")
        XCTAssertEqual(result["preservedNativeEvent"] as? Bool, true)
    }

    func testStoredExtensionDirectoryIsCopiedBeforeCompatibilityIsApplied()
        throws
    {
        let fileManager = FileManager.default
        let source = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-stored-source-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: source) }
        let workerURL = source.appending(path: "background/background.js")
        try fileManager.createDirectory(
            at: workerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("globalThis.original = true;".utf8).write(to: workerURL)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "background": [
                "service_worker": "background/background.js",
                "type": "module",
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: source.appending(path: "manifest.json")
        )
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in
                XCTFail("A stored directory must be copied, not expanded.")
            }
        )

        let prepared = try XCTUnwrap(
            preparer.prepareStoredResource(
                source,
                requestedPermissions: ["nativeMessaging", "notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )

        XCTAssertNotEqual(prepared.resourceURL, source)
        let preparedBackgroundDocuments =
            try FileManager.default.contentsOfDirectory(
                at: prepared.resourceURL,
                includingPropertiesForKeys: nil
            ).filter {
                $0.lastPathComponent.hasPrefix(
                    "crest-webextension-background-"
                ) && $0.pathExtension == "html"
            }
        XCTAssertEqual(preparedBackgroundDocuments.count, 1)
        let storedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: source.appending(path: "manifest.json")
                )
            ) as? [String: Any]
        )
        let storedBackground = try XCTUnwrap(
            storedManifest["background"] as? [String: Any]
        )
        XCTAssertEqual(
            storedBackground["service_worker"] as? String,
            "background/background.js"
        )
        XCTAssertNil(storedBackground["page"])
    }

    func testCompatibilitySelectionUsesCapabilitiesInsteadOfExtensionIdentity() {
        XCTAssertTrue(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresCompatibilityLayer(
                    requestedPermissions: [
                        "nativeMessaging",
                        "notifications",
                    ]
                )
        )
        XCTAssertFalse(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresCompatibilityLayer(
                    requestedPermissions: ["storage", "alarms"]
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
                requestedPermissions: ["nativeMessaging", "webNavigation"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )

        let compatibilityScript = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(compatibilityScript.contains("onHistoryStateUpdated"))
        XCTAssertTrue(compatibilityScript.contains("onTabReplaced"))
        XCTAssertTrue(compatibilityScript.contains("not_controllable"))
        let preparedWorker = try String(
            contentsOf: workerURL,
            encoding: .utf8
        )
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
                expandArchive: { archive, destination in
                    XCTAssertEqual(archive, archiveURL)
                    let workerURL = destination.appending(
                        path: "background.js"
                    )
                    try fileManager.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                    try Data("globalThis.started = true;".utf8).write(
                        to: workerURL
                    )
                    let manifest: [String: Any] = [
                        "manifest_version": 3,
                        "background": [
                            "service_worker": "background.js"
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

        XCTAssertNotEqual(prepared.resourceURL, archiveURL)
        XCTAssertNotNil(prepared.retainedAccess)
        XCTAssertTrue(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresCompatibilityLayer(
                    requestedPermissions: storedInstallation
                        .requestedPermissions
                )
        )
    }

    func testContextMenuTransportDoesNotHideAnAuthoredNativeMessagingPermission() {
        XCTAssertEqual(
            BrowserWebExtensionCompatibilityPackagePreparer
                .internalGrantedPermissions(
                    requestedPermissions: ["contextMenus"]
                ),
            ["nativeMessaging"]
        )
        XCTAssertEqual(
            BrowserWebExtensionCompatibilityPackagePreparer
                .internalGrantedPermissions(
                    requestedPermissions: ["menus"]
                ),
            ["nativeMessaging"]
        )
        XCTAssertTrue(
            BrowserWebExtensionCompatibilityPackagePreparer
                .internalGrantedPermissions(
                    requestedPermissions: [
                        "contextMenus",
                        "nativeMessaging",
                    ]
                ).isEmpty
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
            "pejdijmoenmkgeppbflobdenhhabjlaj"
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
        let compatibilityScript = try String(
            contentsOf: generatedJavaScriptURL(
                in: prepared.resourceURL,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(compatibilityScript.contains("onHistoryStateUpdated"))
        let preparedWorker = try String(
            contentsOf: prepared.resourceURL.appending(
                path: "background/index.js"
            ),
            encoding: .utf8
        )
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

    func testServiceClientIdentityScopesVerifiedStoreRuntimeBySpace()
        throws
    {
        let work = SpaceID()
        let personal = SpaceID()

        let workClient = BrowserExtensionServiceClientID.scoped(
            extensionID: darkReaderID,
            spaceID: work
        )
        let personalClient = BrowserExtensionServiceClientID.scoped(
            extensionID: darkReaderID,
            spaceID: personal
        )

        XCTAssertNotEqual(workClient, personalClient)
        XCTAssertTrue(workClient.rawValue.contains(darkReaderID))
        XCTAssertTrue(personalClient.rawValue.contains(darkReaderID))
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

    func testContentBridgeAddsCrestButtonBesideJapaneseStoreAction()
        async throws
    {
        let configuration = WKWebViewConfiguration()
        let proxy = BrowserChromeWebStoreContentBridge.install(
            in: configuration.userContentController,
            receive: { _ in }
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = ChromeWebStoreNavigationWaiter(webView: webView)
        let request = URLRequest(
            url: URL(
                string:
                    "https://chromewebstore.google.com/detail/google-translate/aapbdbdomjkkjkaonfhkkikfgjllcleb?hl=ja"
            )!
        )

        try await navigation.load(
            request,
            responseHTML: """
                <html>
                  <body>
                    <main>
                      <section>
                        <h1>Google 翻訳</h1>
                        <button aria-label="共有">共有</button>
                        <button disabled><span>Chrome に追加</span></button>
                      </section>
                    </main>
                  </body>
                </html>
                """
        )

        let crestButtonExists =
            try await webView.evaluateJavaScript(
                """
                Boolean(document.querySelector(
                  'button:disabled + ' +
                  '[data-crest-chrome-web-store-button="aapbdbdomjkkjkaonfhkkikfgjllcleb"]'
                ))
                """
            ) as? Bool
        XCTAssertEqual(crestButtonExists, true)
        withExtendedLifetime(proxy) {}
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

    func testFreshStoreInstallDeliversContextMenuInstallLifecycle()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try replacementInstallationFixture(
            permissions: ["contextMenus"],
            backgroundScript: """
                chrome.runtime.onInstalled.addListener(() => {
                    chrome.contextMenus.create({
                        id: "fresh-image",
                        title: "Fresh Image Action",
                        contexts: ["image"]
                    });
                });
                """
        )
        defer { try? fileManager.removeItem(at: fixture.rootURL) }
        let webpageMenuRegistry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: fixture.packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(),
            webpageMenuRegistry: webpageMenuRegistry
        )
        pool.setNativeMessagingHandler(
            BrowserNativeMessagingService(
                capability: .available,
                resolver: BrowserNativeMessagingHostManifestResolver(
                    searchDirectories: []
                ),
                webpageMenuRegistry: webpageMenuRegistry
            )
        )
        let space = BrowserSession.preview.spaces[0]
        let publisherHash =
            BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString

        _ = try await pool.installChromeWebStoreExtension(
            replacementCandidate(
                item: fixture.item,
                extensionID: fixture.extensionID,
                archiveData: fixture.archiveData,
                packageHash: String(repeating: "a", count: 64),
                publisherHash: publisherHash,
                requestedPermissions: ["contextMenus"]
            ),
            in: space
        )
        let context = try XCTUnwrap(
            pool.loadedContext(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )
        )
        let clientID = BrowserExtensionServiceClientID.scoped(
            extensionID: fixture.extensionID.rawValue,
            spaceID: space.id
        )
        var definitions: [BrowserExtensionWebpageMenuDefinition] = []
        for _ in 0..<200 {
            definitions = webpageMenuRegistry.definitions(for: clientID)
            if !definitions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(definitions.map(\.id), ["string:fresh-image"])
        XCTAssertEqual(definitions.first?.contexts, ["image"])
        XCTAssertNil(
            webpageMenuRegistry.pendingInstallLifecycleMessage(for: clientID)
        )
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
        version: String = "1.0",
        requestedPermissions: [String] = []
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
            requestedPermissions: requestedPermissions,
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
        version: String = "1.0",
        permissions: [String] = ["storage", "tabs"],
        backgroundScript: String? = nil
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
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Replacement Rollback Probe",
            "version": version,
            "permissions": permissions,
        ]
        if let backgroundScript {
            manifest["background"] = ["service_worker": "background.js"]
            try Data(backgroundScript.utf8).write(
                to: sourceURL.appending(path: "background.js")
            )
        }
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
        includesPublisherProof: Bool = true,
        zipData suppliedZipData: Data? = nil
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
            suppliedZipData
            ?? Data([0x50, 0x4b, 0x03, 0x04])
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

    func load(_ request: URLRequest, responseHTML: String) async throws {
        guard let webView else {
            throw BrowserChromeWebStoreTestError.releasedWebView
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(
                request,
                responseHTML: responseHTML
            )
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

private final class ChromeWebStoreTestSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    func webView(
        _ webView: WKWebView,
        start urlSchemeTask: any WKURLSchemeTask
    ) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(
                BrowserChromeWebStoreTestError.releasedWebView
            )
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: "text/html",
            expectedContentLength: -1,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data("<html><body></body></html>".utf8))
        urlSchemeTask.didFinish()
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask: any WKURLSchemeTask
    ) {}
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
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        replyHandler(nil, BrowserExtensionNativeMessagingError.unavailable)
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
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
