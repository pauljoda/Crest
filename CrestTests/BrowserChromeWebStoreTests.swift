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

    /// A web view whose document really is an extension page.
    ///
    /// The compatibility runtime works out which process it is running in from
    /// `location.href`: a document served from the extension's own base URL is
    /// an extension page, and anything else is a content script, where a
    /// background-only namespace such as `idle` is legitimately absent. A bare
    /// `WKWebView` sits at `about:blank`, so a test that means to exercise the
    /// extension-page contract has to load one.
    private func extensionPageWebView(
        at baseURL: URL
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ChromeWebStoreTestSchemeHandler(),
            forURLScheme: try XCTUnwrap(baseURL.scheme)
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = ChromeWebStoreNavigationWaiter(webView: webView)
        try await navigation.load(URLRequest(url: baseURL))
        return webView
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
                "permissions": ["debugger", "storage"],
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
        XCTAssertEqual(candidate.requestedPermissions, ["debugger", "storage"])
        XCTAssertEqual(
            candidate.format.sourceDisplayName,
            "Local Chrome Package"
        )
        let storeItem = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string: "https://chromewebstore.google.com/detail/permission-probe/\(fixture.extensionID.rawValue)")!
            ))
        let storeProvider = BrowserChromeWebStoreProvider(
            verifier: BrowserCRX3Verifier(requiredPublisherKeyHash: fixture.publisherKeyHash),
            download: { url in
                (fixture.crxData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        let storeCandidate = try await storeProvider.candidate(for: storeItem)
        XCTAssertEqual(
            storeCandidate.requestedPermissions, ["debugger", "storage"],
            "The install review must disclose debugger access even when WebKit omits it.")
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

    /// The official Claude extension is a module worker. Its bootstrap can
    /// only `import` the compatibility layer — an ES module has no scope a
    /// `const { chrome } = …` binding could shadow — so its code reads the
    /// live `globalThis.chrome`, exactly as every extension page does. The
    /// tabs facade, which carries `tabs.group`, `tabs.ungroup`, and the
    /// `Tab.groupId` mirror, used to exist only on the scoped root a classic
    /// worker's bootstrap binds; Claude's `chrome.tabs.group` was `undefined`,
    /// its own try/catch swallowed the TypeError, and every browser tool
    /// failed with "anchor tab group not established". A dedicated Worker
    /// with no lexical binding is the same view a module worker has.
    func testAModuleWorkerReadsTheTabsFacadeFromTheLiveRoot() async throws {
        let fileManager = FileManager.default
        let fixture = try privilegedFixtureCompatibilityRuntime(
            named: "crest-webextension-module-worker-tabs-test",
            permissions: ["tabs", "tabGroups"]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        // Held for the whole probe: a temporary web view is deallocated while
        // the Worker's reply is still pending. The runtime travels as a string
        // literal inside the function body, like every sibling test, rather
        // than through `arguments`.
        let webView = WKWebView()
        let evaluated = try await webView.callAsyncJavaScript(
            """
            const script = [
                \(Self.javaScriptLiteral(Self.moduleWorkerFixtureNativeRoot)),
                \(Self.javaScriptLiteral(fixture.source)),
                \(Self.javaScriptLiteral(Self.moduleWorkerFixtureProbe))
            ].join("\\n");
            const url = URL.createObjectURL(
                new Blob([script], { type: "text/javascript" })
            );
            return await new Promise((resolve) => {
                let worker;
                try {
                    worker = new Worker(url);
                } catch (error) {
                    resolve(JSON.stringify({ error: String(error) }));
                    return;
                }
                const timeout = setTimeout(
                    () => resolve(JSON.stringify({ error: "worker timed out" })),
                    4000
                );
                worker.onmessage = (event) => {
                    clearTimeout(timeout);
                    resolve(event.data);
                };
                worker.onerror = (event) => {
                    clearTimeout(timeout);
                    resolve(JSON.stringify({ error: String(event.message) }));
                };
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluated as? String).utf8)
            ) as? [String: Any]
        )
        XCTAssertNil(result["error"], String(describing: result["error"]))
        XCTAssertEqual(result["isWorker"] as? Bool, true)
        XCTAssertEqual(
            result["group"] as? String, "function",
            "`tabs.group` must exist on the live root a module worker reads."
        )
        XCTAssertEqual(result["ungroup"] as? String, "function")
        XCTAssertEqual(
            result["scopedGroup"] as? String, "function",
            "The classic-worker scoped root keeps the same facade."
        )
        XCTAssertEqual(
            result["sameFacade"] as? Bool, true,
            "Both roots must hand out one tabs facade, not two."
        )
        XCTAssertEqual(result["getStillWorks"] as? Bool, true)
        XCTAssertEqual(
            result["eventIdentity"] as? Bool, true,
            """
            The facade must hand back WebKit's own event object: WebKit \
            dispatches through its native graph, so a listener registered \
            via the facade has to land on the native event.
            """
        )
        withExtendedLifetime(webView) {}
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: [value]
        )
        let array = String(decoding: data ?? Data(), as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    /// A worker-shaped WebKit root: no `document`, native `runtime` and
    /// `tabs` objects, and — deliberately — no `const { chrome } =` binding
    /// in front of the extension code.
    private static let moduleWorkerFixtureNativeRoot = """
        const noop = () => {};
        const event = () => ({
            addListener: noop, removeListener: noop, hasListener: () => false
        });
        const nativeTabs = {
            get: (id) => Promise.resolve({
                id, index: 0, windowId: 7, url: "https://example.com/"
            }),
            query: () => Promise.resolve([]),
            sendMessage: () => Promise.resolve(undefined),
            onUpdated: event(), onRemoved: event(), onActivated: event()
        };
        globalThis.nativeTabs = nativeTabs;
        globalThis.chrome = {
            runtime: {
                id: "fixture",
                getURL: (path) => "chrome-extension://fixture/" + path,
                getManifest: () => ({ manifest_version: 3 }),
                sendMessage: () => Promise.resolve(undefined),
                connect: () => ({
                    name: "", postMessage: noop, disconnect: noop,
                    onMessage: event(), onDisconnect: event()
                }),
                connectNative: () => ({
                    name: "", postMessage: noop, disconnect: noop,
                    onMessage: event(), onDisconnect: event()
                }),
                onMessage: event(), onConnect: event(),
                onInstalled: event(), onStartup: event()
            },
            tabs: nativeTabs,
            windows: {
                getCurrent: () => Promise.resolve({ id: 7, type: "normal" }),
                getAll: () => Promise.resolve([{ id: 7, type: "normal" }])
            },
            storage: {
                local: { get: () => Promise.resolve({}), set: () => Promise.resolve() },
                session: { get: () => Promise.resolve({}), set: () => Promise.resolve() },
                onChanged: event()
            }
        };
        globalThis.browser = globalThis.chrome;
        """

    private static let moduleWorkerFixtureProbe = """
        (async () => {
            let getStillWorks = false;
            try {
                const tab = await chrome.tabs.get(3);
                getStillWorks = tab?.id === 3 && tab.groupId === -1;
            } catch {}
            const scoped = globalThis.__crestWebExtensionScopedAPI?.chrome;
            postMessage(JSON.stringify({
                isWorker: typeof globalThis.document === "undefined",
                group: typeof chrome.tabs.group,
                ungroup: typeof chrome.tabs.ungroup,
                scopedGroup: typeof scoped?.tabs?.group,
                sameFacade: scoped?.tabs === chrome.tabs,
                eventIdentity:
                    chrome.tabs.onUpdated === globalThis.nativeTabs.onUpdated,
                getStillWorks
            }));
        })();
        """

    /// A module worker stays a worker.
    ///
    /// Preparation used to host it in a generated background document; it now
    /// keeps WebKit's native worker boundary and points `service_worker` at a
    /// generated bootstrap that imports the compatibility layer before the
    /// extension's own module. Extension pages still receive the layer through
    /// an injected `<script src>` and nothing else — their markup is vendor
    /// source and is not rewritten.
    func testCompatibilityLayerKeepsAModuleWorkerBehindItsBootstrapAndInjectsPages()
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
        let backgroundBootstrapName = try XCTUnwrap(
            background["service_worker"] as? String
        )
        XCTAssertNil(background["page"])
        XCTAssertNil(background["scripts"])
        // The bootstrap is an ES module: it `import`s the compatibility layer
        // and then the extension's own module worker, so the prepared manifest
        // has to keep declaring the module type.
        XCTAssertEqual(background["type"] as? String, "module")
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
            backgroundBootstrapName.hasPrefix(
                "crest-webextension-background-bootstrap-"
            )
        )
        XCTAssertTrue(backgroundBootstrapName.hasSuffix(".js"))
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

        let backgroundBootstrap = try String(
            contentsOf: root.appending(
                path: backgroundBootstrapName
            ),
            encoding: .utf8
        )
        let compatibilityImport =
            #"import "./\#(compatibilityScriptName)";"#
        XCTAssertEqual(
            backgroundBootstrap.components(
                separatedBy: compatibilityImport
            ).count,
            2,
            "The bootstrap must import the compatibility layer exactly once."
        )
        let workerImport = #"import "./background/background.js";"#
        XCTAssertTrue(backgroundBootstrap.contains(workerImport))
        let compatibilityRange = try XCTUnwrap(
            backgroundBootstrap.range(of: compatibilityImport)
        )
        let workerRange = try XCTUnwrap(
            backgroundBootstrap.range(of: workerImport)
        )
        XCTAssertLessThan(
            compatibilityRange.lowerBound,
            workerRange.lowerBound,
            "The compatibility layer must load before the worker module."
        )
        // A module bootstrap has no scoped-API handoff: `import` shares one
        // module scope, unlike the `importScripts` bootstrap.
        XCTAssertFalse(backgroundBootstrap.contains("__crest"))

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
        let backgroundBootstrapFingerprint = Data(
            SHA256.hash(data: Data(backgroundBootstrap.utf8)).prefix(8)
        ).hexString
        XCTAssertEqual(
            backgroundBootstrapName,
            "crest-webextension-background-bootstrap-\(backgroundBootstrapFingerprint).js"
        )
        // A coarse guard that the generated runtime still carries every
        // surface a portable package leans on. `addHostAccessRequest` and
        // `wrappedJSObject` are deliberately absent: the runtime no longer
        // publishes members it cannot deliver, so feature detection reports
        // them missing and packages take their own fallback path.
        for requiredSurface in [
            "notifications",
            "onCreatedNavigationTarget",
            "getUserSettings",
            "passwordSavingEnabled",
            "storageManaged",
            "onChanged",
            "installFallbacks",
            "namespaceFacade",
            "installNamespaceFacades",
            "installNativeAliases",
            "installMissingRoot",
            "installEventFacade",
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
        ] {
            XCTAssertTrue(
                compatibilityScript.contains(requiredSurface),
                "Missing compatibility surface: \(requiredSurface)"
            )
        }
        XCTAssertTrue(compatibilityScript.contains("declaredManifest"))
        XCTAssertTrue(compatibilityScript.contains("options.url"))
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
        // The extension's own markup is vendor source. Injection is the only
        // edit preparation makes to it: attributes, empty or not, survive.
        XCTAssertTrue(preparedPopup.contains("<body aria-label"))
        XCTAssertTrue(preparedPopup.contains("placeholder=\"\""))
        XCTAssertTrue(preparedPopup.contains("data-i18n-title='  '"))
        XCTAssertTrue(
            preparedPopup.contains(#"aria-label="Known message""#)
        )
        XCTAssertTrue(preparedPopup.contains(#"<script src="popup.js">"#))
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

    /// Builds a package whose only background is a plain document script and
    /// returns its generated compatibility runtime.
    ///
    /// `permissions` and `optionalPermissions` are what the fixture manifest
    /// declares, which is what decides whether a permission-gated namespace is
    /// published at all.
    private func storageFixtureCompatibilityRuntime(
        named name: String,
        permissions: [String] = ["storage"],
        optionalPermissions: [String] = []
    ) throws -> (root: URL, source: String) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        try Data("globalThis.contentStarted = true;".utf8).write(
            to: root.appending(path: "content.js")
        )
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Storage Fixture",
            "version": "1.0",
            "permissions": permissions,
            "background": ["scripts": ["background.js"]],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ]
            ],
        ]
        if !optionalPermissions.isEmpty {
            manifest["optional_permissions"] = optionalPermissions
        }
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
                requestedPermissions: permissions + optionalPermissions,
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        return (
            root,
            try String(
                contentsOf: generatedJavaScriptURL(
                    in: root,
                    prefix: "crest-webextension-compatibility"
                ),
                encoding: .utf8
            )
        )
    }

    /// A non-extension `location` makes this the content-script contract.
    private static let storageFixtureNativeRoot = """
        const channelNames = [];
        const NativeBroadcastChannel = globalThis.BroadcastChannel;
        Object.defineProperty(globalThis, "BroadcastChannel", {
            configurable: true,
            value: class extends NativeBroadcastChannel {
                constructor(name) {
                    super(name);
                    channelNames.push(name);
                }
            }
        });
        const stored = {};
        const nativeLocal = {
            get(keys, callback) {
                const result = {};
                if (keys === null || keys === undefined) {
                    Object.assign(result, stored);
                } else if (Array.isArray(keys)) {
                    for (const key of keys) {
                        if (key in stored) result[key] = stored[key];
                    }
                } else if (typeof keys === "string") {
                    if (keys in stored) result[keys] = stored[keys];
                } else if (keys && typeof keys === "object") {
                    for (const key of Object.keys(keys)) {
                        result[key] = key in stored
                            ? stored[key]
                            : keys[key];
                    }
                }
                if (callback) {
                    callback(result);
                    return;
                }
                return Promise.resolve(result);
            },
            set(items, callback) {
                Object.assign(stored, items);
                if (callback) {
                    callback();
                    return;
                }
                return Promise.resolve();
            },
            onChanged: {
                addListener() {},
                removeListener() {}
            }
        };
        Object.defineProperty(globalThis, "chrome", {
            configurable: true,
            value: {
                runtime: {
                    getManifest() { return { manifest_version: 3 }; },
                    id: "fixture-extension-id"
                },
                storage: { local: nativeLocal }
            }
        });
        """

    /// A content script runs on the HOST PAGE origin. A BroadcastChannel
    /// opened there would publish every stored value to the page, let the page
    /// forge `storage.onChanged`, and let two extensions on one tab hear each
    /// other. Chrome delivers `storage.onChanged` to content scripts natively,
    /// so the relay must exist only in privileged extension contexts.
    func testCompatibilityLayerKeepsTheStorageRelayOutOfContentScripts()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try storageFixtureCompatibilityRuntime(
            named: "crest-webextension-storage-content-script-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.storageFixtureNativeRoot)
            \(fixture.source)
            const events = [];
            chrome.storage.onChanged.addListener((changes, areaName) => {
                events.push({ changes, areaName });
            });
            await chrome.storage.local.set({ token: "one" });
            await new Promise((resolve) => setTimeout(resolve, 30));
            return JSON.stringify({
                href: String(globalThis.location?.href ?? ""),
                channelNames,
                eventCount: events.length,
                areaName: events[0]?.areaName
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
        XCTAssertFalse(
            try XCTUnwrap(result["href"] as? String).hasPrefix(
                fixtureRuntimeIdentity.baseURL.absoluteString
            ),
            "The fixture must run outside the extension origin."
        )
        XCTAssertEqual(
            result["channelNames"] as? [String],
            [],
            "A content script must never open the storage relay channel."
        )
        XCTAssertEqual(result["eventCount"] as? Int, 1)
        XCTAssertEqual(result["areaName"] as? String, "local")

        // A privileged relay stays scoped to one extension origin and refuses
        // a payload that claims a different one.
        XCTAssertTrue(
            fixture.source.contains(
                "storageBridgeMarker + \":\" + storageBridgeScope"
            )
        )
        XCTAssertTrue(
            fixture.source.contains(
                "payload.origin !== extensionBaseURL"
            )
        )
        XCTAssertTrue(
            fixture.source.contains("if (isPrivilegedExtensionContext) {")
        )
    }

    /// Chrome defines a permission-gated namespace only when the manifest
    /// asked for it, and portable extensions feature-detect exactly that.
    ///
    /// Publishing an emulated namespace nobody requested hands an extension an
    /// API whose every call the capability broker refuses — and, for the
    /// namespaces backed by a watch port, a reconnect it refuses forever.
    func testAnUndeclaredPermissionKeepsItsNamespaceOffTheCompatibilityLayer()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try storageFixtureCompatibilityRuntime(
            named: "crest-webextension-undeclared-namespace-test",
            permissions: []
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.storageFixtureNativeRoot)
            \(fixture.source)
            return JSON.stringify({
                onChanged: typeof chrome.storage.onChanged,
                managed: typeof chrome.storage.managed,
                runtime: typeof chrome.runtime.getURL
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
            result["onChanged"] as? String,
            "undefined",
            "A package that never declared \"storage\" must keep WebKit's own storage surface."
        )
        XCTAssertEqual(result["managed"] as? String, "undefined")
        XCTAssertEqual(
            result["runtime"] as? String,
            "function",
            "runtime needs no permission, so it must stay compatible."
        )
    }

    /// Chrome publishes a namespace an extension listed under
    /// `optional_permissions` before the grant arrives; the individual calls
    /// fail until it does. Presence in either list is therefore enough.
    func testAnOptionalPermissionStillPublishesItsNamespace() async throws {
        let fileManager = FileManager.default
        let fixture = try storageFixtureCompatibilityRuntime(
            named: "crest-webextension-optional-namespace-test",
            permissions: [],
            optionalPermissions: ["storage"]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.storageFixtureNativeRoot)
            \(fixture.source)
            return typeof chrome.storage.onChanged;
            """,
            arguments: [:],
            contentWorld: .page
        )
        XCTAssertEqual(evaluatedResult as? String, "object")
    }

    /// The runtime must say what it cannot do rather than fail quietly.
    ///
    /// Every construct below replaced a silent drop: a discarded error, a
    /// dropped URL pattern, an ignored notification option, a blocking
    /// listener whose return value goes nowhere, and a watch port that
    /// reconnected forever against a refusal that will never change.
    func testCompatibilityRuntimeReportsWhatItCannotHonor() throws {
        let fileManager = FileManager.default
        let fixture = try storageFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        for construct in [
            "const namespacePermissions",
            "const namespaceIsDeclared",
            "declaredManifest.optional_permissions",
            "const invokeCallbackWithLastError",
            "Unchecked runtime.lastError",
            "const capabilityWatch",
            "stopped reconnecting",
            "does not consume blocking responses",
            "warnUnsupportedNotificationOptions",
            "const authoredMenuPatterns",
        ] {
            XCTAssertTrue(
                fixture.source.contains(construct),
                "Missing diagnostic construct: \(construct)"
            )
        }
        for removed in [
            "supportedMenuPattern",
            "connectNotificationWatch",
            "connectIdleWatch",
        ] {
            XCTAssertFalse(
                fixture.source.contains(removed),
                "Superseded construct still present: \(removed)"
            )
        }
    }

    /// Chrome fires `storage.onChanged` for every `set`, including one that
    /// stores an identical value. A value-signature suppression window
    /// swallowed the second write, so dedup must correlate delivery paths
    /// instead of values.
    /// A foreign native event must not swallow this context's own next write.
    ///
    /// Cross-path correlation exists because WebKit can echo a write this
    /// context already reported. It ran in both directions, so a native event
    /// for key X raised by a SIBLING context left a token that cancelled this
    /// context's own write of X for the next 250 ms — and in the exact case
    /// the relay exists for, where WebKit does not echo a context's own write,
    /// the listener then saw nothing at all. A native arrival may only consume
    /// a Crest emission that already happened.
    func testAForeignNativeChangeDoesNotSwallowThisContextsOwnWrite()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try storageFixtureCompatibilityRuntime(
            named: "crest-webextension-storage-foreign-native-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let webView = WKWebView()
        let evaluatedResult = try await webView.callAsyncJavaScript(
            """
            const stored = {};
            const nativeChangeListeners = new Set();
            const nativeLocal = {
                get(keys, callback) {
                    const result = {};
                    if (keys === null || keys === undefined) {
                        Object.assign(result, stored);
                    } else if (typeof keys === "string") {
                        if (keys in stored) result[keys] = stored[keys];
                    } else if (Array.isArray(keys)) {
                        for (const key of keys) {
                            if (key in stored) result[key] = stored[key];
                        }
                    } else if (keys && typeof keys === "object") {
                        for (const key of Object.keys(keys)) {
                            result[key] = key in stored
                                ? stored[key]
                                : keys[key];
                        }
                    }
                    if (callback) { callback(result); return; }
                    return Promise.resolve(result);
                },
                set(items, callback) {
                    Object.assign(stored, items);
                    if (callback) { callback(); return; }
                    return Promise.resolve();
                },
                onChanged: { addListener() {}, removeListener() {} }
            };
            const nativeRootChanged = {
                addListener(listener) {
                    nativeChangeListeners.add(listener);
                },
                removeListener(listener) {
                    nativeChangeListeners.delete(listener);
                },
                hasListener(listener) {
                    return nativeChangeListeners.has(listener);
                }
            };
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; },
                        id: "fixture-extension-id"
                    },
                    storage: {
                        local: nativeLocal,
                        onChanged: nativeRootChanged
                    }
                }
            });
            \(fixture.source)
            const events = [];
            chrome.storage.onChanged.addListener((changes) => {
                events.push(Object.keys(changes ?? {}).join("+"));
            });
            // A sibling context wrote `token`; WebKit reports that natively.
            for (const listener of Array.from(nativeChangeListeners)) {
                listener(
                    { token: { newValue: "elsewhere" } },
                    "local"
                );
            }
            await new Promise((resolve) => setTimeout(resolve, 20));
            const afterForeignNative = events.length;
            // This context now writes the same key, inside the window.
            await chrome.storage.local.set({ token: "mine" });
            await new Promise((resolve) => setTimeout(resolve, 40));
            const afterOwnWrite = events.length;
            // Identical consecutive writes still each fire.
            await chrome.storage.local.set({ token: "mine" });
            await new Promise((resolve) => setTimeout(resolve, 40));
            return JSON.stringify({
                afterForeignNative,
                afterOwnWrite,
                total: events.length,
                keys: events
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

        XCTAssertEqual(result["afterForeignNative"] as? Int, 1)
        XCTAssertEqual(
            result["afterOwnWrite"] as? Int,
            2,
            "The context's own write must reach its own listener."
        )
        XCTAssertEqual(result["total"] as? Int, 3)
        XCTAssertEqual(
            result["keys"] as? [String],
            ["token", "token", "token"]
        )
    }

    func testIdenticalConsecutiveStorageWritesEachDispatchOneChange()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try storageFixtureCompatibilityRuntime(
            named: "crest-webextension-storage-duplicate-write-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.storageFixtureNativeRoot)
            \(fixture.source)
            const events = [];
            chrome.storage.onChanged.addListener((changes, areaName) => {
                events.push({ changes, areaName });
            });
            const areaEvents = [];
            chrome.storage.local.onChanged.addListener((changes) => {
                areaEvents.push(changes);
            });
            await chrome.storage.local.set({ token: "one" });
            await chrome.storage.local.set({ token: "one" });
            await new Promise((resolve) => setTimeout(resolve, 30));
            return JSON.stringify({
                eventCount: events.length,
                areaEventCount: areaEvents.length,
                firstChange: events[0]?.changes?.token,
                secondChange: events[1]?.changes?.token,
                secondChangeKeys: Object.keys(
                    events[1]?.changes?.token ?? {}
                )
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
            result["eventCount"] as? Int,
            2,
            "Two identical writes are two events in Chrome."
        )
        XCTAssertEqual(result["areaEventCount"] as? Int, 2)
        XCTAssertEqual(
            result["firstChange"] as? [String: String],
            ["newValue": "one"]
        )
        XCTAssertEqual(
            result["secondChange"] as? [String: String],
            ["oldValue": "one", "newValue": "one"]
        )
        XCTAssertEqual(
            result["secondChangeKeys"] as? [String],
            ["oldValue", "newValue"],
            "A Crest change object must carry Chrome's key order."
        )
    }

    /// A dual-environment MV3 package still declares a service worker, but
    /// preparation collapses it to a background document. The runtime has to
    /// read the prepared shape, otherwise it virtualizes `alarms.onAlarm`
    /// with no worker left to feed it.
    func testDualEnvironmentBackgroundDeclaresTheDocumentAlarmOwner() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-dual-environment-test-\(UUID().uuidString)",
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
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )

        let dualManifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Dual Environment Fixture",
            "version": "1.0",
            "permissions": ["alarms"],
            "background": [
                "service_worker": "background.js",
                "scripts": ["background.js"],
                "preferred_environment": ["service_worker"],
            ],
        ]
        XCTAssertEqual(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .preparedBackgroundEnvironment(dualManifest),
            "document"
        )
        XCTAssertEqual(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .preparedBackgroundEnvironment([
                    "manifest_version": 3,
                    "background": ["service_worker": "background.js"],
                ]),
            "worker"
        )

        try JSONSerialization.data(withJSONObject: dualManifest).write(
            to: root.appending(path: "manifest.json")
        )
        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: ["alarms"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let preparedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try Data(
                    contentsOf: root.appending(path: "manifest.json")
                )
            ) as? [String: Any]
        )
        let preparedBackground = try XCTUnwrap(
            preparedManifest["background"] as? [String: Any]
        )
        XCTAssertNil(preparedBackground["service_worker"])
        XCTAssertNotNil(preparedBackground["scripts"])

        let source = try String(
            contentsOf: generatedJavaScriptURL(
                in: root,
                prefix: "crest-webextension-compatibility"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains(#"backgroundEnvironment = "document""#),
            "A dual-environment package runs its background as a document."
        )
        XCTAssertTrue(
            source.contains(#"backgroundEnvironment !== "worker""#),
            "Alarms must virtualize only for a real worker background."
        )
        XCTAssertFalse(
            source.contains(#"backgroundEnvironment = "worker""#)
        )
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
        // Three native probes, and the fourth call deliberately makes none:
        // the two authored `contains` calls, plus the removal of the OPTIONAL
        // grant, which asks WebKit what is actually held before deciding and
        // settles to `false` when — as here — the native reply never arrives.
        // Removing `*://api.example.test/*` asks nothing: the manifest lists
        // it under `host_permissions`, so it is required access and is refused
        // from the manifest alone. Neither removal reaches native `remove`.
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
            // The runtime publishes a permission-gated namespace only when the
            // manifest declares one of its permissions, the way Chrome does.
            "permissions": ["privacy"],
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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

    /// Giving up on a watch must not outlive the reason for giving up.
    ///
    /// The broker refuses a watch whose permission the package does not hold,
    /// and an OPTIONAL permission is exposed before it is granted. Six
    /// refusals during that window used to retire the watch for the life of
    /// the context, so the grant the user then gave never delivered a single
    /// event. A fresh `addListener` restores the budget; simply obtaining a
    /// port does not, because `connectNative` returns one even for a refusal
    /// the broker completes by dropping it.
    func testAnAbandonedCapabilityWatchRetriesAfterAFreshListener()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-idle-watch-retry-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let permissions = ["idle", "nativeMessaging"]
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Idle Watch Retry Fixture",
            "version": "1.0",
            "optional_permissions": permissions,
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
                requestedPermissions: permissions,
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
            // Collapse the backoff so six refusals fit in a test.
            const nativeSetTimeout = globalThis.setTimeout.bind(globalThis);
            globalThis.setTimeout = (fn, delay, ...rest) =>
                nativeSetTimeout(fn, Math.min(Number(delay) || 0, 1), ...rest);
            let connectCount = 0;
            let refuse = true;
            const makePort = () => {
                const disconnectListeners = new Set();
                const port = {
                    onMessage: {
                        addListener() {},
                        removeListener() {}
                    },
                    onDisconnect: {
                        addListener(listener) {
                            disconnectListeners.add(listener);
                        },
                        removeListener(listener) {
                            disconnectListeners.delete(listener);
                        }
                    },
                    postMessage() {},
                    disconnect() {},
                    drop() {
                        for (const listener of Array.from(
                            disconnectListeners
                        )) {
                            listener(port);
                        }
                    }
                };
                return port;
            };
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: {
                    runtime: {
                        getManifest() { return { manifest_version: 3 }; },
                        connectNative() {
                            connectCount += 1;
                            const port = makePort();
                            if (refuse) {
                                // The broker answers a refusal by dropping the
                                // port it just handed back.
                                nativeSetTimeout(() => port.drop(), 0);
                            }
                            return port;
                        }
                    }
                }
            });
            \(source)
            const settle = () =>
                new Promise((resolve) => nativeSetTimeout(resolve, 60));
            const listener = () => {};
            browser.idle.onStateChanged.addListener(listener);
            for (let attempt = 0; attempt < 12; attempt += 1) {
                await settle();
            }
            const afterRefusals = connectCount;
            await settle();
            const stillAbandoned = connectCount;
            // The user grants the optional permission; the package
            // re-registers its listener.
            refuse = false;
            browser.idle.onStateChanged.removeListener(listener);
            browser.idle.onStateChanged.addListener(listener);
            await settle();
            return JSON.stringify({
                afterRefusals,
                stillAbandoned,
                afterRegrant: connectCount
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
            result["afterRefusals"] as? Int,
            6,
            "The watch stops after six consecutive refusals."
        )
        XCTAssertEqual(
            result["stillAbandoned"] as? Int,
            6,
            "It must not keep reconnecting against a standing refusal."
        )
        XCTAssertEqual(
            result["afterRegrant"] as? Int,
            7,
            "A fresh addListener is a new intent, and retries once more."
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
        // A namespace is published only when the manifest declares one of its
        // permissions, so the fixture declares every namespace this test then
        // reads back.
        let fixturePermissions = [
            "menus", "nativeMessaging", "notifications", "webNavigation",
            "webRequest",
        ]
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Runtime Identity Fixture",
            "version": "1.0",
            "permissions": fixturePermissions,
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
                requestedPermissions: fixturePermissions,
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
        let webView = try await extensionPageWebView(
            at: runtimeIdentity.baseURL
        )
        let evaluatedResult = try await webView.callAsyncJavaScript(
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
            // WebKit's own namespaces are ordinary extensible objects, and
            // Crest fills its missing members in on them rather than wrapping
            // them: a Proxy has no native wrapper, so wrapping a live
            // namespace strands every listener registered through it. A
            // sealed stand-in would therefore be testing a shape WebKit never
            // presents.
            const nativeWebNavigation = {
                onCommitted: nativeCommittedEvent,
                getFrame() {
                    return this === nativeWebNavigation
                        ? { receiver: "native-namespace" }
                        : undefined;
                }
            };
            const nativeRequestEvent = Object.freeze({
                receiver: "native-request-event"
            });
            const nativeWebRequest = {
                onBeforeRequest: nativeRequestEvent
            };
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
            nativeRoot.i18n = nativeI18n;
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
        // Crest used to publish an empty `wrappedJSObject` so a Firefox-shaped
        // feature probe would not throw. The runtime no longer answers a probe
        // for a privilege it cannot grant: an extension that finds the name
        // missing takes its script-injection fallback, which is what it would
        // do in Chrome.
        XCTAssertEqual(
            result["wrappedJSObjectType"] as? String,
            "undefined"
        )
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
            "permissions": [
                "contextMenus", "downloads", "offscreen", "sidePanel",
            ],
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
                URL(string: "about:blank")
            )
        )
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )
        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: [
                    "contextMenus", "downloads", "offscreen", "sidePanel",
                ],
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
                const brokerRequests = [];
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
                    },
                    sendNativeMessage(host, message) {
                        brokerRequests.push({ host, message });
                        if (message.api === "offscreen.hasDocument") {
                            return Promise.resolve({ hasDocument: true });
                        }
                        if (message.api === "offscreen.createDocument") {
                            return Promise.resolve({ created: true });
                        }
                        if (message.api === "offscreen.closeDocument") {
                            return Promise.resolve({ closed: true });
                        }
                        return Promise.resolve({ downloadID: 73 });
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
                // The complete namespace must accept the same awaited startup
                // call that previously exposed the one-member stub regression.
                const sidePanelType = typeof chrome.sidePanel;
                const sidePanelBrowserType = typeof browser.sidePanel;
                await chrome.sidePanel.setOptions({enabled: false});
                await chrome.offscreen.createDocument({
                    url: chrome.runtime.getURL("offscreen.html"),
                    reasons: ["DOM_SCRAPING"],
                    justification: "Convert an image"
                });
                const hasOffscreenDocument =
                    await chrome.offscreen.hasDocument();
                await chrome.offscreen.closeDocument();
                const downloadID = await chrome.downloads.download({
                    url: "data:image/jpeg;base64,/9j/2Q==",
                    filename: "converted.jpg",
                    saveAs: true
                });
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
                    brokerRequests,
                    downloadID,
                    hasOffscreenDocument,
                    sidePanelType,
                    sidePanelBrowserType,
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
            result["sidePanelType"] as? String,
            "object",
            """
            A requested sidePanel permission publishes the complete schema.
            """
        )
        XCTAssertEqual(
            result["sidePanelBrowserType"] as? String,
            "object",
            "The browser root aliases the same complete surface."
        )
        XCTAssertEqual(result["downloadID"] as? Int, 73)
        XCTAssertEqual(result["hasOffscreenDocument"] as? Bool, true)
        let brokerRequests = try XCTUnwrap(
            result["brokerRequests"] as? [[String: Any]]
        )
        XCTAssertTrue(
            brokerRequests.contains { ($0["message"] as? [String: Any])?["api"] as? String == "sidePanel.setOptions" })
        let offscreenCreateRequest = try XCTUnwrap(
            brokerRequests.first {
                ($0["message"] as? [String: Any])?["api"] as? String
                    == "offscreen.createDocument"
            }
        )
        let offscreenCreateMessage = try XCTUnwrap(
            offscreenCreateRequest["message"] as? [String: Any]
        )
        XCTAssertEqual(
            offscreenCreateMessage["url"] as? String,
            "crest-extension://context-menu-fixture/offscreen.html"
        )
        XCTAssertEqual(
            offscreenCreateMessage["reasons"] as? [String],
            ["DOM_SCRAPING"]
        )
        XCTAssertEqual(
            offscreenCreateMessage["justification"] as? String,
            "Convert an image"
        )
        XCTAssertTrue(
            brokerRequests.contains {
                ($0["message"] as? [String: Any])?["api"] as? String
                    == "offscreen.hasDocument"
            }
        )
        XCTAssertTrue(
            brokerRequests.contains {
                ($0["message"] as? [String: Any])?["api"] as? String
                    == "offscreen.closeDocument"
            }
        )
        let downloadRequest = try XCTUnwrap(
            brokerRequests.first {
                ($0["message"] as? [String: Any])?["api"] as? String
                    == "downloads.download"
            }
        )
        XCTAssertEqual(
            downloadRequest["host"] as? String,
            BrowserNativeMessagingService.capabilityBrokerIdentifier
        )
        let downloadMessage = try XCTUnwrap(
            downloadRequest["message"] as? [String: Any]
        )
        XCTAssertEqual(downloadMessage["api"] as? String, "downloads.download")
        XCTAssertEqual(downloadMessage["filename"] as? String, "converted.jpg")
        XCTAssertEqual(downloadMessage["saveAs"] as? Bool, true)
        XCTAssertEqual(
            downloadMessage["url"] as? String,
            "data:image/jpeg;base64,/9j/2Q=="
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

    /// A missing event is filled in on the live native namespace itself.
    ///
    /// Crest used to publish each namespace behind an accessor that rebuilt a
    /// facade on every read, so a member deleted from the native object came
    /// back. Wrapping a live native namespace is now forbidden — WebKit
    /// resolves an extension event target by unwrapping the native object
    /// behind the namespace, and a Proxy has no native wrapper, so the wrap
    /// stranded every listener registered through it (see
    /// `testNativeNamespacesAreNeverReplacedWithAFacade`). The placeholder is
    /// therefore an ordinary configurable property on WebKit's own object: it
    /// is installed once, it leaves the native events untouched, and a later
    /// `delete` really deletes it.
    func testCompatibilityMembersInstallOnTheLiveNativeNamespace() async throws {
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
            // A permission-gated namespace is published only when the manifest
            // declares one of its permissions, the way Chrome does.
            "permissions": ["webNavigation"],
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
                runtimeIdentity: privilegedFixtureRuntimeIdentity
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
            const installed =
                typeof chrome.webNavigation
                    .onCreatedNavigationTarget?.addListener;
            const descriptor = Reflect.getOwnPropertyDescriptor(
                nativeWebNavigation,
                "onCreatedNavigationTarget"
            );
            Reflect.deleteProperty(
                nativeWebNavigation,
                "onCreatedNavigationTarget"
            );
            return JSON.stringify({
                installed,
                installedOnTheNativeObject: descriptor !== undefined,
                configurable: descriptor?.configurable === true,
                afterDeletion:
                    typeof chrome.webNavigation
                        .onCreatedNavigationTarget?.addListener,
                namespaceIsNative:
                    chrome.webNavigation === nativeWebNavigation,
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

        XCTAssertEqual(result["installed"] as? String, "function")
        XCTAssertEqual(result["installedOnTheNativeObject"] as? Bool, true)
        XCTAssertEqual(
            result["configurable"] as? Bool,
            true,
            "Chrome's own API members are configurable; pinning ours broke extensions that monkeypatch them."
        )
        XCTAssertEqual(
            result["afterDeletion"] as? String,
            "undefined",
            "Nothing re-materializes a deleted member: there is no facade in front of the native namespace."
        )
        XCTAssertEqual(result["namespaceIsNative"] as? Bool, true)
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
        // A module worker keeps WebKit's worker boundary: preparation writes a
        // module bootstrap beside the copy rather than a background document.
        let preparedBackgroundBootstraps =
            try FileManager.default.contentsOfDirectory(
                at: prepared.resourceURL,
                includingPropertiesForKeys: nil
            ).filter {
                $0.lastPathComponent.hasPrefix(
                    "crest-webextension-background-bootstrap-"
                ) && $0.pathExtension == "js"
            }
        XCTAssertEqual(preparedBackgroundBootstraps.count, 1)
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

    func testPreparedPackageKeepsPublishedWorkerResourcesAddressableAfterRefresh()
        throws
    {
        let fileManager = FileManager.default
        let source = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-version-refresh-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: source) }
        try fileManager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("globalThis.original = true;".utf8).write(
            to: source.appending(path: "background.js")
        )

        func writeManifest(version: String) throws {
            let manifest: [String: Any] = [
                "manifest_version": 3,
                "name": "Version Refresh Fixture",
                "version": version,
                "background": ["service_worker": "background.js"],
            ]
            try JSONSerialization.data(withJSONObject: manifest).write(
                to: source.appending(path: "manifest.json"),
                options: [.atomic]
            )
        }

        func preparedManifest(at resourceURL: URL) throws -> [String: Any] {
            try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data(
                        contentsOf: resourceURL.appending(path: "manifest.json")
                    )
                ) as? [String: Any]
            )
        }

        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in }
        )
        try writeManifest(version: "1.0")
        let first = try XCTUnwrap(
            preparer.prepareStoredResource(
                source,
                requestedPermissions: ["notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        defer {
            try? fileManager.removeItem(
                at: first.resourceURL.deletingLastPathComponent()
            )
        }
        let firstManifest = try preparedManifest(at: first.resourceURL)
        let firstBackground = try XCTUnwrap(
            firstManifest["background"] as? [String: Any]
        )
        let firstBootstrap = try XCTUnwrap(
            firstBackground["service_worker"] as? String
        )
        let firstCompatibility = try XCTUnwrap(
            fileManager.contentsOfDirectory(
                at: first.resourceURL,
                includingPropertiesForKeys: nil
            ).first {
                $0.lastPathComponent.hasPrefix(
                    "crest-webextension-compatibility-"
                ) && $0.pathExtension == "js"
            }?.lastPathComponent
        )

        try writeManifest(version: "1.1")
        let refreshed = try XCTUnwrap(
            preparer.prepareStoredResource(
                source,
                requestedPermissions: ["notifications"],
                runtimeIdentity: fixtureRuntimeIdentity
            )
        )
        let refreshedManifest = try preparedManifest(at: refreshed.resourceURL)
        let refreshedBackground = try XCTUnwrap(
            refreshedManifest["background"] as? [String: Any]
        )
        let refreshedBootstrap = try XCTUnwrap(
            refreshedBackground["service_worker"] as? String
        )

        XCTAssertEqual(refreshed.resourceURL, first.resourceURL)
        XCTAssertNotEqual(refreshedBootstrap, firstBootstrap)
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: refreshed.resourceURL.appending(path: firstBootstrap).path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath:
                    refreshed.resourceURL.appending(path: firstCompatibility)
                    .path
            )
        )
    }

    /// Every portable package receives the same browser contract.
    ///
    /// The permission list cannot answer whether preparation is needed:
    /// runtime, action, window, and worker APIs require no manifest
    /// permission, so a package declaring nothing interesting still depends on
    /// the layer. The selection is therefore unconditional — and, just as
    /// importantly, still not a function of extension identity.
    func testCompatibilityLayerAppliesToEveryPortablePackage() {
        XCTAssertTrue(
            BrowserChromeWebStoreCompatibilityPackagePreparer
                .requiresCompatibilityLayer(
                    requestedPermissions: [
                        "nativeMessaging",
                        "notifications",
                    ]
                )
        )
        XCTAssertTrue(
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

    /// A verified store package has to run on the origin the rest of the web
    /// already knows it by: embedding checks, CORS exemptions, and
    /// web-accessible-resource probes all string-match
    /// `chrome-extension://<store id>`.
    func testRuntimeBaseURLIsTheVerifiedChromeStoreOrigin() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let source = BrowserChromeWebStoreSource(
            extensionID: id,
            storeURL: URL(
                string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
            )!,
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString
        )
        let work = SpaceID()
        let personal = SpaceID()

        for spaceID in [work, personal] {
            XCTAssertEqual(
                BrowserExtensionRuntimeIdentifierPolicy.identity(
                    extensionID: darkReaderID,
                    source: .chromeWebStore(source),
                    spaceID: spaceID
                ).baseURL.absoluteString,
                "chrome-extension://\(darkReaderID)/"
            )
        }
    }

    /// Nothing but a verified store package earns the store origin. An
    /// unpacked or locally installed package — and a store record whose ID
    /// does not match the package being loaded — keeps the hashed per-Space
    /// host.
    func testRuntimeBaseURLStaysPerSpaceForUnverifiedSources() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let source = BrowserChromeWebStoreSource(
            extensionID: id,
            storeURL: URL(
                string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReaderID)"
            )!,
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: BrowserCRX3Verifier.chromeWebStorePublisherKeyHash.hexString
        )
        let work = SpaceID()
        let personal = SpaceID()

        let unpacked = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: darkReaderID,
            source: .unpackedPackage,
            spaceID: work
        ).baseURL
        XCTAssertEqual(unpacked.absoluteString, hashedBaseURL(darkReaderID, work))
        XCTAssertNotEqual(
            unpacked,
            BrowserExtensionRuntimeIdentifierPolicy.identity(
                extensionID: darkReaderID,
                source: .unpackedPackage,
                spaceID: personal
            ).baseURL
        )
        // The record is verified, but it does not name this package.
        XCTAssertEqual(
            BrowserExtensionRuntimeIdentifierPolicy.identity(
                extensionID: "local.probe",
                source: .chromeWebStore(source),
                spaceID: work
            ).baseURL.absoluteString,
            hashedBaseURL("local.probe", work)
        )
    }

    /// The escape hatch for a Space that would share a `WKWebsiteDataStore`
    /// with another Space running the same package: WebKit keys service-worker
    /// registrations by origin inside a data store, so the second Space takes
    /// the hashed host back rather than colliding on a dormant registration.
    func testRuntimeBaseURLFallsBackWhenASpaceSharesADataStore() throws {
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

        let identity = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: darkReaderID,
            source: .chromeWebStore(source),
            spaceID: spaceID,
            sharesDataStoreWithAnotherContext: true
        )

        XCTAssertEqual(
            identity.baseURL.absoluteString,
            hashedBaseURL(darkReaderID, spaceID)
        )
        // Only the origin moves. The extension-visible identity, and the data
        // record it is stored under, stay the verified store ID.
        XCTAssertEqual(identity.uniqueIdentifier, darkReaderID)
        XCTAssertEqual(identity.referenceEnvironment, .chromium)
    }

    private func hashedBaseURL(_ extensionID: String, _ spaceID: SpaceID) -> String {
        let originIdentifier =
            "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
        let digest = SHA256.hash(data: Data(originIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "chrome-extension://extension-\(digest)/"
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
            // The Mac install path prepares the compatibility package through
            // the pool's own stored-resource preparer, which is what
            // production wires. A pool left on the default identity preparer
            // installs no compatibility layer, so the extension's declared
            // menus and its onInstalled ack never appear.
            storedResourcePreparer:
                BrowserStoreWebExtensionStoredResourcePreparer(
                    fileManager: fileManager
                ),
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
            registry: registry,
            // Production wires this preparer, and the Mac install path
            // prepares the compatibility package through it. A live audit run
            // on the default identity preparer would measure a runtime the
            // app never ships.
            storedResourcePreparer:
                BrowserStoreWebExtensionStoredResourcePreparer(
                    fileManager: fileManager
                )
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
            registry: registry,
            // Production wires this preparer, and the Mac install path
            // prepares the compatibility package through it. A live audit run
            // on the default identity preparer would measure a runtime the
            // app never ships.
            storedResourcePreparer:
                BrowserStoreWebExtensionStoredResourcePreparer(
                    fileManager: fileManager
                )
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

    // MARK: - Route-driven ownership

    /// A runtime identity whose extension origin is `about:blank`.
    ///
    /// The compatibility runtime decides it is in a privileged extension
    /// context by comparing `location.href` against the extension's base URL.
    /// A bare `WKWebView` is already an `about:blank` document, so naming that
    /// as the base URL puts the runtime on the extension-page path without a
    /// navigation — which is the only way to reach the broker-backed
    /// namespaces at all, since none of them are published to content scripts.
    private var privilegedFixtureRuntimeIdentity: BrowserExtensionRuntimeIdentity {
        BrowserExtensionRuntimeIdentity(
            extensionID: "fixture-extension-id",
            uniqueIdentifier: "fixture-extension-id.space.personal",
            baseURL: URL(string: "about:blank")!
        )
    }

    /// Builds a package whose compatibility runtime will run as an extension
    /// page, and returns its generated source.
    private func privilegedFixtureCompatibilityRuntime(
        named name: String,
        permissions: [String],
        manifestEntries: [String: Any] = [:]
    ) throws -> (root: URL, source: String) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Route Fixture",
            "version": "1.0",
            "permissions": permissions,
            "background": ["scripts": ["background.js"]],
        ]
        manifest.merge(manifestEntries) { _, replacement in replacement }
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
                requestedPermissions: permissions,
                runtimeIdentity: privilegedFixtureRuntimeIdentity
            )
        )
        return (
            root,
            try String(
                contentsOf: generatedJavaScriptURL(
                    in: root,
                    prefix: "crest-webextension-compatibility"
                ),
                encoding: .utf8
            )
        )
    }

    /// A WebKit 27 shaped root: `idle` and `action` both already exist, and
    /// each carries the member Crest also implements.
    private static let routeFixtureNativeRoot = """
        globalThis.fixture = {};
        fixture.nativeQueryState = function queryState() {
            return "native-implementation";
        };
        fixture.nativeGetUserSettings = function getUserSettings() {
            return "native-implementation";
        };
        fixture.nativeGetAll = function getAll() {
            return "native-implementation";
        };
        fixture.idle = {
            queryState: fixture.nativeQueryState,
            setDetectionInterval() {},
            onStateChanged: {
                addListener() {},
                removeListener() {},
                hasListener() { return false; }
            }
        };
        fixture.action = { getUserSettings: fixture.nativeGetUserSettings };
        fixture.commands = { getAll: fixture.nativeGetAll };
        Object.defineProperty(globalThis, "chrome", {
            configurable: true,
            value: {
                runtime: {
                    id: "fixture-extension-id",
                    getURL(path = "") { return "about:blank#" + path; },
                    getManifest() { return { manifest_version: 3 }; },
                    sendNativeMessage() {
                        return Promise.reject(new Error("no broker"));
                    }
                },
                idle: fixture.idle,
                action: fixture.action,
                commands: fixture.commands
            }
        });
        """

    /// An `emulated` route means Crest's implementation IS the contract, so it
    /// has to replace a native property rather than defer to it.
    ///
    /// `installFallbacks` used to install only where the native property was
    /// `undefined`, which made every emulated API a hostage to the next OS
    /// release: the day WebKit defines `idle.queryState`, an extension would
    /// silently get an implementation Crest has never authorized through its
    /// capability broker, and the matrix row saying otherwise would be wrong.
    func testEmulatedRouteReplacesAPreExistingNativeMember() async throws {
        let fileManager = FileManager.default
        let fixture = try privilegedFixtureCompatibilityRuntime(
            named: "crest-webextension-emulated-route-test",
            permissions: ["idle"]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.routeFixtureNativeRoot)
            \(fixture.source)
            let queryStateResult;
            let queryStateKind;
            try {
                queryStateResult = chrome.idle.queryState(60);
                if (
                    queryStateResult
                    && typeof queryStateResult.then === "function"
                ) {
                    queryStateKind = "promise";
                    // Crest answers through the capability broker, which this
                    // fixture does not provide. Settle it so the rejection is
                    // handled rather than escaping the page.
                    queryStateResult.then(() => {}, () => {});
                } else {
                    queryStateKind = String(queryStateResult);
                }
            } catch {
                queryStateKind = "threw";
            }
            let rejectedNegativeInterval = false;
            try {
                chrome.idle.setDetectionInterval(-1);
            } catch {
                rejectedNegativeInterval = true;
            }
            return JSON.stringify({
                queryStateKind,
                memberIsNotNative:
                    chrome.idle.queryState !== fixture.nativeQueryState,
                namespaceIsNotNative: chrome.idle !== fixture.idle,
                rejectedNegativeInterval
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [String: Any]
        )
        XCTAssertNotEqual(
            result["queryStateKind"] as? String,
            "native-implementation",
            """
            A native idle.queryState answered the call. The emulated route \
            must own the member even when WebKit defines it.
            """
        )
        XCTAssertEqual(result["queryStateKind"] as? String, "promise")
        XCTAssertEqual(result["memberIsNotNative"] as? Bool, true)
        XCTAssertEqual(result["namespaceIsNotNative"] as? Bool, true)
        XCTAssertEqual(
            result["rejectedNegativeInterval"] as? Bool,
            true,
            """
            Crest's idle.setDetectionInterval rejects a negative interval and \
            the fixture's native one does not, so this is what proves the \
            surviving implementation is Crest's.
            """
        )
    }

    /// The mirror image: a `nativePatched` route keeps WebKit's implementation
    /// and its identity, and fills only what is missing.
    func testNativePatchedRouteKeepsAPreExistingNativeMethod() async throws {
        let fileManager = FileManager.default
        let fixture = try privilegedFixtureCompatibilityRuntime(
            named: "crest-webextension-native-patched-route-test",
            permissions: ["idle"]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.routeFixtureNativeRoot)
            \(fixture.source)
            return JSON.stringify({
                // The native namespace object itself is never rewritten.
                nativeIdentityKept:
                    fixture.action.getUserSettings
                        === fixture.nativeGetUserSettings,
                // A namespace with no Crest-owned member is passed through
                // untouched, identity and all.
                untouchedIdentityKept:
                    chrome.commands.getAll === fixture.nativeGetAll,
                // And the native implementation is the one that runs.
                answeredBy: String(chrome.action.getUserSettings())
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(result["nativeIdentityKept"] as? Bool, true)
        XCTAssertEqual(result["untouchedIdentityKept"] as? Bool, true)
        XCTAssertEqual(
            result["answeredBy"] as? String,
            "native-implementation"
        )
    }

    /// WebKit trunk enabled a native `offscreen` API on 2026-08-28 behind a
    /// pref that defaults on.
    ///
    /// The hiding rule fires only for a namespace WebKit actually provides, so
    /// the row had to move from Unavailable to Partial. Without this, a macOS
    /// update replaces a broker-managed document lifecycle with an untested
    /// native one and nothing in the product notices.
    func testOffscreenIsHiddenFromTheNativeSurfaceWhenRequested() throws {
        let hidden =
            BrowserExtensionAPICompatibilityMatrix
            .unsupportedWebKitAPIs(requestedPermissions: ["offscreen"])
        XCTAssertTrue(
            hidden.contains("browser.offscreen"),
            """
            A package requesting `offscreen` must not see WebKit's native \
            implementation: Crest's emulation owns the document lifecycle.
            """
        )

        // A package that never asked for the permission is unaffected: Chrome
        // does not define the namespace for it either.
        XCTAssertFalse(
            BrowserExtensionAPICompatibilityMatrix
                .unsupportedWebKitAPIs(requestedPermissions: [])
                .contains("browser.offscreen")
        )
    }

    /// Crest owns every member and keeps WebKit's partial namespace hidden.
    func testSidePanelIsEmulatedWhileNativeSurfaceIsHidden() throws {
        XCTAssertEqual(
            BrowserExtensionAPICompatibilityMatrix
                .namespaceRoutes["sidePanel"],
            "emulated"
        )
        XCTAssertTrue(
            BrowserExtensionAPICompatibilityMatrix
                .unsupportedWebKitAPIs(requestedPermissions: ["sidePanel"])
                .contains("browser.sidePanel"),
            """
            A package requesting `sidePanel` must not reach WebKit's partial \
            implementation. Crest supplies the complete replacement.
            """
        )
        XCTAssertEqual(
            BrowserExtensionAPICompatibilityMatrix.memberRoutes.filter { $0.key.hasPrefix("sidePanel.") }.count, 10)
    }

    /// A namespace Crest refuses is never published, however it is reached.
    ///
    /// A refused namespace must remain absent even when WebKit supplies two
    /// API roots and the extension requests the corresponding permission.
    func testARefusedNamespaceIsAbsentFromBothExtensionRoots() async throws {
        let fileManager = FileManager.default
        let fixture = try privilegedFixtureCompatibilityRuntime(
            named: "crest-webextension-refused-namespace-test",
            permissions: ["history"]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            const nativeRuntime = {
                id: "fixture-extension-id",
                getURL(path = "") { return "about:blank#" + path; },
                getManifest() { return { manifest_version: 3 }; },
                sendNativeMessage() {
                    return Promise.reject(new Error("no broker"));
                }
            };
            // Two roots over one context, which is what WebKit publishes.
            // Neither carries `history`, because `unsupportedWebKitAPIs`
            // hides it — so a namespace appearing here could only have come
            // from Crest, or from Crest aliasing one root onto the other.
            Object.defineProperty(globalThis, "chrome", {
                configurable: true,
                value: { runtime: nativeRuntime }
            });
            Object.defineProperty(globalThis, "browser", {
                configurable: true,
                value: { runtime: nativeRuntime }
            });
            \(fixture.source)
            return JSON.stringify({
                chromeType: typeof chrome.history,
                browserType: typeof browser.history,
                chromeInOperator: "history" in chrome,
                browserInOperator: "history" in browser,
                chromeKeys: Object.keys(chrome).filter(
                    (key) => key.toLowerCase().includes("history")
                ),
                // The namespaces the manifest did ask for and Crest does
                // implement are still there, so this is absence by route
                // rather than a runtime that failed to install.
                runtimeInstalled: typeof chrome.runtime.getURL
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(result["runtimeInstalled"] as? String, "function")
        XCTAssertEqual(result["chromeType"] as? String, "undefined")
        XCTAssertEqual(result["browserType"] as? String, "undefined")
        XCTAssertEqual(result["chromeInOperator"] as? Bool, false)
        XCTAssertEqual(result["browserInOperator"] as? Bool, false)
        XCTAssertEqual(result["chromeKeys"] as? [String], [])
    }

    /// An emulated namespace publishes its whole schema or nothing.
    ///
    /// Chrome extensions feature-detect on the namespace and then assume the
    /// schema behind it, so a partial namespace is worse than an absent one:
    /// the guard passes and the next member access throws inside whatever
    /// awaited it. Every member `emulatedSurface` declares is therefore
    /// present, the ones Crest cannot deliver fail honestly — a rejected
    /// promise, or `runtime.lastError` for the callback form — and the events
    /// among them accept listeners and report them back.
    func testEveryEmulatedNamespacePublishesItsCompleteSchemaSurface()
        async throws
    {
        let fileManager = FileManager.default
        let matrix = BrowserExtensionAPICompatibilityMatrix.self
        let surface = matrix.emulatedSurface

        XCTAssertEqual(
            Set(surface.keys),
            Set(
                matrix.contracts.filter { $0.crest == .emulated }
                    .map(\.namespace)
            ),
            """
            Every emulated namespace declares its surface, and only an \
            emulated namespace does. A namespace missing from \
            `emulatedSurface` publishes whatever the runtime happens to \
            implement, which is the shape this rule exists to prevent.
            """
        )

        for namespace in surface.keys.sorted() {
            let declared = try XCTUnwrap(surface[namespace])
            let fixture = try privilegedFixtureCompatibilityRuntime(
                named: "crest-webextension-emulated-surface-\(namespace)",
                permissions: matrix.namespacePermissions[namespace] ?? [],
                manifestEntries: namespace == "sidebarAction"
                    ? ["sidebar_action": ["default_panel": "panel.html"]] : [:]
            )
            defer { try? fileManager.removeItem(at: fixture.root) }

            // The members Crest does not implement, as the matrix routes
            // them. Probing one of each shape is what distinguishes a filler
            // that fails honestly from a no-op that reports success for work
            // that never happened.
            let placeholders = declared.filter {
                matrix.memberRoutes["\(namespace).\($0)"] == "presenceOnly"
            }
            let methodProbe = placeholders.first { !$0.hasPrefix("on") }
            let eventProbe = placeholders.first { $0.hasPrefix("on") }

            let evaluatedResult = try await WKWebView().callAsyncJavaScript(
                """
                \(Self.emulatedSurfaceFixtureNativeRoot)
                \(fixture.source)
                const namespace = \(Self.javaScriptLiteral(namespace));
                const declared = \(Self.javaScriptLiteral(declared));
                const methodProbe = \(Self.javaScriptLiteralOrNull(methodProbe));
                const eventProbe = \(Self.javaScriptLiteralOrNull(eventProbe));
                const object = chrome[namespace];
                if (!object) {
                    return JSON.stringify({ published: false });
                }
                const result = {
                    published: true,
                    missing: declared.filter((member) => !(member in object)),
                    keys: Object.keys(object)
                };
                if (methodProbe) {
                    const returned = object[methodProbe]();
                    result.promiseRejection =
                        returned && typeof returned.then === "function"
                            ? await returned.then(
                                () => "RESOLVED",
                                (error) => String(error?.message ?? error)
                            )
                            : "NOT A PROMISE: " + String(returned);
                    result.callbackLastError = await new Promise(
                        (resolve) => {
                            object[methodProbe](() => resolve(
                                String(
                                    chrome.runtime.lastError?.message ?? ""
                                )
                            ));
                        }
                    );
                }
                if (eventProbe) {
                    const listener = () => {};
                    const event = object[eventProbe];
                    event.addListener(listener);
                    result.event = {
                        addListener: typeof event.addListener,
                        removeListener: typeof event.removeListener,
                        hasListener: event.hasListener(listener)
                    };
                }
                return JSON.stringify(result);
                """,
                arguments: [:],
                contentWorld: .page
            )
            let result = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
                ) as? [String: Any]
            )
            XCTAssertEqual(
                result["published"] as? Bool,
                true,
                "`chrome.\(namespace)` was requested and must be published."
            )
            XCTAssertEqual(
                result["missing"] as? [String],
                [],
                """
                `chrome.\(namespace)` is missing members its reference schema \
                defines. A package that detects the namespace will call them.
                """
            )
            let keys = Set(try XCTUnwrap(result["keys"] as? [String]))
            XCTAssertTrue(
                keys.isSuperset(of: declared),
                "`chrome.\(namespace)` keys \(keys.sorted()) ⊉ \(declared)"
            )

            if let methodProbe {
                XCTAssertEqual(
                    result["promiseRejection"] as? String,
                    "\(namespace).\(methodProbe) is not available in Crest.",
                    """
                    `\(namespace).\(methodProbe)` must reject and say why. A \
                    resolved promise leaves an extension waiting on work \
                    Crest never started.
                    """
                )
                XCTAssertEqual(
                    result["callbackLastError"] as? String,
                    "\(namespace).\(methodProbe) is not available in Crest.",
                    """
                    The callback form reports the same failure through \
                    `runtime.lastError`, which is where Chrome puts it.
                    """
                )
            }
            if let eventProbe {
                let event = try XCTUnwrap(
                    result["event"] as? [String: Any],
                    "`\(namespace).\(eventProbe)` must be an event object."
                )
                XCTAssertEqual(event["addListener"] as? String, "function")
                XCTAssertEqual(event["removeListener"] as? String, "function")
                XCTAssertEqual(
                    event["hasListener"] as? Bool,
                    true,
                    """
                    A presence-only event keeps a real registry: \
                    `hasListener` cannot deny a listener just added, or a \
                    package cannot tell registration from a Crest bug.
                    """
                )
            }
        }
    }

    /// A WebKit root with none of the emulated namespaces on it, which is
    /// what `unsupportedWebKitAPIs` leaves behind for a package that
    /// requested them.
    private static let emulatedSurfaceFixtureNativeRoot = """
        const nativeRuntime = {
            id: "fixture-extension-id",
            getURL(path = "") { return "about:blank#" + path; },
            getManifest() { return { manifest_version: 3 }; },
            sendNativeMessage() {
                return Promise.reject(new Error("no broker"));
            }
        };
        Object.defineProperty(globalThis, "chrome", {
            configurable: true,
            value: { runtime: nativeRuntime }
        });
        Object.defineProperty(globalThis, "browser", {
            configurable: true,
            value: { runtime: nativeRuntime }
        });
        """

    /// A JSON value is a JavaScript expression, which is all these fixtures
    /// need to carry a matrix-derived list into the evaluated runtime.
    private static func javaScriptLiteral(_ value: Any) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed, .withoutEscapingSlashes]
            ),
            let literal = String(data: data, encoding: .utf8)
        else { return "null" }
        return literal
    }

    /// The absent case is a JavaScript `null`, which the fixtures test for.
    private static func javaScriptLiteralOrNull(_ value: String?) -> String {
        guard let value else { return "null" }
        return javaScriptLiteral(value)
    }

    /// The runtime's webRequest event list is derived from the matrix.
    ///
    /// It used to be a literal beside the table that hides
    /// `webRequest.onAuthRequired`, so the runtime normalized — and handed
    /// back — the very event Crest removes from WebKit's surface because it
    /// cannot honor a blocking credential prompt.
    func testWebRequestEventListExcludesTheHiddenAuthEvent() throws {
        let fileManager = FileManager.default
        let fixture = try privilegedFixtureCompatibilityRuntime(
            named: "crest-webextension-webrequest-event-list-test",
            permissions: ["webRequest"]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let events = try XCTUnwrap(
            BrowserExtensionAPICompatibilityMatrix
                .namespaceEventMembers["webRequest"]
        )
        XCTAssertFalse(events.contains("onAuthRequired"))
        XCTAssertTrue(events.contains("onBeforeRequest"))
        XCTAssertTrue(events.contains("onCompleted"))

        // The generated script must consult that list rather than carry its
        // own copy.
        XCTAssertTrue(
            fixture.source.contains(#"eventMembersOf("webRequest")"#)
        )
        let publishedEvents = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    try XCTUnwrap(
                        Self.generatedJSONLiteral(
                            named: "namespaceEventMembers",
                            in: fixture.source
                        )
                    ).utf8
                )
            ) as? [String: [String]]
        )
        XCTAssertEqual(publishedEvents["webRequest"], events)
        XCTAssertFalse(
            try XCTUnwrap(publishedEvents["webRequest"])
                .contains("onAuthRequired")
        )
    }

    /// A root carrying a native object for every namespace the routed
    /// fallback set touches.
    private static let identityFixtureNativeRoot = """
        globalThis.fixture = {};
        const fixtureEvent = () => ({
            addListener() {},
            removeListener() {},
            hasListener() { return false; },
            hasListeners() { return false; }
        });
        fixture.nativeGetCalls = 0;
        fixture.nativeLocalGet = function get(keys, callback) {
            fixture.nativeGetCalls += 1;
            callback?.({});
            return Promise.resolve({});
        };
        fixture.storage = {
            local: {
                get: fixture.nativeLocalGet,
                set(items, callback) {
                    callback?.();
                    return Promise.resolve();
                },
                onChanged: fixtureEvent()
            },
            onChanged: fixtureEvent()
        };
        fixture.action = { getUserSettings() {}, setIcon() {} };
        fixture.webNavigation = {
            getAllFrames() {},
            onCommitted: fixtureEvent()
        };
        fixture.webRequest = {
            onBeforeRequest: fixtureEvent(),
            onCompleted: fixtureEvent()
        };
        fixture.permissions = {
            contains() {},
            getAll() {},
            request() {},
            remove() {}
        };
        fixture.scripting = { executeScript() {} };
        fixture.idle = {
            queryState() { return "native-implementation"; },
            setDetectionInterval() {},
            onStateChanged: fixtureEvent()
        };
        Object.defineProperty(globalThis, "chrome", {
            configurable: true,
            value: {
                runtime: {
                    id: "fixture-extension-id",
                    getURL(path = "") { return "about:blank#" + path; },
                    getManifest() { return { manifest_version: 3 }; },
                    sendNativeMessage() {
                        return Promise.reject(new Error("no broker"));
                    }
                },
                storage: fixture.storage,
                action: fixture.action,
                webNavigation: fixture.webNavigation,
                webRequest: fixture.webRequest,
                permissions: fixture.permissions,
                scripting: fixture.scripting,
                idle: fixture.idle
            }
        });
        """

    /// WebKit resolves an extension event target by reading the frame's live
    /// `chrome` / `browser` global and unwrapping the native object behind the
    /// root (`WebExtensionContextProxy::enumerateFramesAndNamespaceObjects`);
    /// namespaces and their events are then reached through WebKit's own
    /// object graph. A Proxy has no native wrapper, so a Proxy root strands
    /// every listener — which is how a root Proxy broke message routing
    /// outright on 2026-08-29. The roots therefore stay WebKit's, and a
    /// namespace is replaced in place only where Crest has a facade that hands
    /// back WebKit's event objects untouched (`alarms`, `extension`, `tabs`;
    /// see `testAModuleWorkerReadsTheTabsFacadeFromTheLiveRoot`). These
    /// namespaces have no such facade and must remain WebKit's own objects.
    ///
    /// `installFallbacks` used to pin each namespace it touched
    /// non-configurable, which made `installNamespaceFacades` fail silently
    /// and never wrap an existing native namespace. Removing that pinning
    /// would have resurrected the wrapping by accident, so the rule is now
    /// stated in the code instead of being an emergent property of a pin.
    func testNativeNamespacesAreNeverReplacedWithAFacade() async throws {
        let fileManager = FileManager.default
        let fixture = try privilegedFixtureCompatibilityRuntime(
            named: "crest-webextension-native-identity-test",
            permissions: [
                "storage", "webNavigation", "webRequest", "scripting", "idle",
            ]
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.identityFixtureNativeRoot)
            \(fixture.source)
            let idleIsCrest = false;
            try {
                // Crest's implementation validates the interval; the
                // fixture's native one does not.
                chrome.idle.setDetectionInterval(-1);
            } catch {
                idleIsCrest = true;
            }
            await chrome.storage.local.get("token");
            return JSON.stringify({
                action: chrome.action === fixture.action,
                webNavigation:
                    chrome.webNavigation === fixture.webNavigation,
                webRequest: chrome.webRequest === fixture.webRequest,
                permissions: chrome.permissions === fixture.permissions,
                scripting: chrome.scripting === fixture.scripting,
                idleIsNative: chrome.idle === fixture.idle,
                idleIsCrest,
                storageDelegatesToNative: fixture.nativeGetCalls > 0
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [String: Any]
        )

        for namespace in [
            "action", "webNavigation", "webRequest", "permissions",
            "scripting",
        ] {
            XCTAssertEqual(
                result[namespace] as? Bool,
                true,
                """
                chrome.\(namespace) is no longer WebKit's own object. A \
                facade over a live native namespace has no native wrapper, \
                so WebKit cannot dispatch events to listeners registered \
                through it.
                """
            )
        }

        // The emulated route is the one exception, and it installs Crest's
        // plain object rather than a Proxy over the native one.
        XCTAssertEqual(result["idleIsNative"] as? Bool, false)
        XCTAssertEqual(result["idleIsCrest"] as? Bool, true)

        // `storage` is the one namespace that genuinely cannot be augmented
        // in place: its cross-context `onChanged` relay predates this rule
        // and does overlay the namespace. That path is deliberately
        // unchanged, and it still delegates to WebKit's implementation
        // rather than replacing it.
        XCTAssertEqual(result["storageDelegatesToNative"] as? Bool, true)
    }

    // MARK: - Extension diagnostics

    /// A native root that records every capability-broker message.
    ///
    /// The diagnostics channel is the only part of the runtime that sends
    /// without being asked, so the recorder is what proves it reported at all.
    private static let diagnosticsFixtureNativeRoot = """
        globalThis.brokerRequests = [];
        Object.defineProperty(globalThis, "chrome", {
            configurable: true,
            value: {
                runtime: {
                    id: "fixture-extension-id",
                    getURL(path = "") { return "about:blank#" + path; },
                    getManifest() { return { manifest_version: 3 }; },
                    sendNativeMessage(host, message) {
                        globalThis.brokerRequests.push({ host, message });
                        return Promise.resolve({ recorded: true });
                    }
                }
            }
        });
        globalThis.diagnosticsReports = () => globalThis.brokerRequests
            .filter((entry) => entry.message?.api === "diagnostics.report")
            .map((entry) => entry.message);
        """

    /// Builds a package whose generated runtime is the one under test, with
    /// console capture on or off.
    ///
    /// The identity decides which process the runtime believes it is in. The
    /// default names `about:blank` as the extension origin, which puts a bare
    /// `WKWebView` on the extension-page path without a navigation; passing
    /// `fixtureRuntimeIdentity` instead makes that same web view a content
    /// script, and makes a document actually served from that base URL a real
    /// extension page.
    private func diagnosticsFixtureCompatibilityRuntime(
        named name: String,
        enablesConsoleCapture: Bool = false,
        runtimeIdentity: BrowserExtensionRuntimeIdentity? = nil
    ) throws -> (root: URL, source: String) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        let permissions = ["idle"]
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Diagnostics Fixture",
                "version": "1.0",
                "permissions": permissions,
                "background": ["scripts": ["background.js"]],
            ] as [String: Any]
        ).write(to: root.appending(path: "manifest.json"))
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager,
            expandArchive: { _, _ in },
            enablesConsoleCapture: enablesConsoleCapture
        )
        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: permissions,
                runtimeIdentity: runtimeIdentity
                    ?? privilegedFixtureRuntimeIdentity
            )
        )
        return (
            root,
            try String(
                contentsOf: generatedJavaScriptURL(
                    in: root,
                    prefix: "crest-webextension-compatibility"
                ),
                encoding: .utf8
            )
        )
    }

    private func evaluatedDiagnosticsReports(
        source: String,
        trigger: String
    ) async throws -> [[String: Any]] {
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.diagnosticsFixtureNativeRoot)
            \(source)
            \(trigger)
            await new Promise((resolve) => setTimeout(resolve, 60));
            return JSON.stringify({
                reports: globalThis.diagnosticsReports(),
                hosts: globalThis.brokerRequests.map((entry) => entry.host)
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [String: Any]
        )
        return try XCTUnwrap(result["reports"] as? [[String: Any]])
    }

    /// Serves an extension page whose own inline scripts install the runtime
    /// and then throw.
    ///
    /// The document has to come from the extension's origin. WebKit sanitizes
    /// an error raised by script it cannot attribute to an origin — anything
    /// injected through `evaluateJavaScript` into `about:blank` arrives as
    /// `ErrorEvent{message: "Script error.", error: null}` — so only a real
    /// same-origin document reproduces what a popup actually reports, stack
    /// included. The scripts are inlined rather than linked because the
    /// generated runtime contains no `<script>`, `</script>`, or `<!--`
    /// sequence for the HTML parser to trip over.
    private func diagnosticsExtensionPageWebView(
        at baseURL: URL,
        scripts: [String]
    ) async throws -> WKWebView {
        let inlined =
            scripts
            .map { "<script>\n\($0)\n</script>" }
            .joined(separator: "\n")
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ChromeWebStoreDocumentSchemeHandler(
                html: "<html><head>\(inlined)</head><body></body></html>"
            ),
            forURLScheme: try XCTUnwrap(baseURL.scheme)
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = ChromeWebStoreNavigationWaiter(webView: webView)
        try await navigation.load(URLRequest(url: baseURL))
        return webView
    }

    /// WebKit reports only what an extension's API callbacks throw. An
    /// uncaught exception in a popup — the shape that left a Bitwarden popup
    /// blank after a two-factor sign-in with nothing to read — reaches nobody,
    /// so the runtime reports it over the capability broker instead.
    ///
    /// This runs on a document actually served from the extension's own
    /// origin, and throws for real from a timer. Both details matter: a
    /// synthetic `ErrorEvent` carries no `error` object, and a throw from
    /// script WebKit cannot attribute to an origin is sanitized to
    /// `"Script error."` with no error object either. Only this shape proves
    /// a report reaches Crest with the stack that names the failing line.
    func testDiagnosticsChannelReportsAnUncaughtExtensionError() async throws {
        let fileManager = FileManager.default
        let fixture = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-error-test",
            runtimeIdentity: fixtureRuntimeIdentity
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let webView = try await diagnosticsExtensionPageWebView(
            at: fixtureRuntimeIdentity.baseURL,
            scripts: [
                Self.diagnosticsFixtureNativeRoot,
                fixture.source,
                """
                globalThis.setTimeout(() => {
                    throw new Error("fixture boom");
                }, 0);
                """,
            ]
        )
        let evaluatedResult = try await webView.callAsyncJavaScript(
            """
            await new Promise((resolve) => setTimeout(resolve, 200));
            return JSON.stringify(globalThis.diagnosticsReports());
            """,
            arguments: [:],
            contentWorld: .page
        )
        let reports = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [[String: Any]]
        )

        XCTAssertEqual(
            reports.count,
            1,
            "One fault must produce exactly one diagnostics report."
        )
        let report = try XCTUnwrap(reports.first)
        let reportedMessage = try XCTUnwrap(report["message"] as? String)
        let reportedStack = try XCTUnwrap(report["stack"] as? String)
        XCTAssertEqual(report["kind"] as? String, "error")
        XCTAssertTrue(
            reportedMessage.contains("fixture boom"),
            """
            The report must carry the failing error's own text. \
            Observed message: \(reportedMessage)
            """
        )
        XCTAssertEqual(
            report["source"] as? String,
            fixtureRuntimeIdentity.baseURL.absoluteString
        )
        XCTAssertFalse(
            reportedStack.isEmpty,
            """
            A report carries the failing stack, bounded to 2000 characters. \
            It is the whole reason this channel exists: the message alone \
            names the fault but not the line that raised it. \
            Observed message: \(reportedMessage). \
            Observed stack: \(reportedStack)
            """
        )
    }

    /// An extension that throws the same fault from a hot handler must not
    /// spend its whole report budget on one broken line, so identical text
    /// from the same document inside a second is reported once.
    func testDiagnosticsChannelCollapsesRepeatedIdenticalFaults()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-dedupe-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let reports = try await evaluatedDiagnosticsReports(
            source: fixture.source,
            trigger: """
                for (let index = 0; index < 2; index += 1) {
                    globalThis.setTimeout(() => {
                        throw new Error("repeated fixture boom");
                    }, 0);
                }
                """
        )

        XCTAssertEqual(
            reports.count,
            1,
            "Two identical faults inside the dedupe window report once."
        )
        XCTAssertEqual(reports.first?["kind"] as? String, "error")
    }

    /// A content script runs on the page's origin. Installing the handlers
    /// there would report the *page's* exceptions as the extension's, and
    /// would hand a hostile page a channel into Crest's broker.
    func testDiagnosticsChannelStaysOutOfContentScripts() async throws {
        let fileManager = FileManager.default
        let fixture = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-content-script-test",
            enablesConsoleCapture: true,
            runtimeIdentity: fixtureRuntimeIdentity
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let reports = try await evaluatedDiagnosticsReports(
            source: fixture.source,
            trigger: """
                globalThis.dispatchEvent(new ErrorEvent("error", {
                    message: "page boom",
                    error: new Error("page boom")
                }));
                console.warn("page warning");
                """
        )

        XCTAssertTrue(
            reports.isEmpty,
            "A content script installs no diagnostics handlers at all."
        )
    }

    /// An extension that throws inside a hot event handler must not be able to
    /// turn the diagnostics channel into a message loop of its own.
    func testDiagnosticsChannelStopsAfterItsReportBudget() async throws {
        let fileManager = FileManager.default
        let fixture = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-rate-limit-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let reports = try await evaluatedDiagnosticsReports(
            source: fixture.source,
            trigger: """
                for (let index = 0; index < 25; index += 1) {
                    globalThis.dispatchEvent(new ErrorEvent("error", {
                        message: `fixture boom ${index}`,
                        error: new Error(`fixture boom ${index}`)
                    }));
                }
                """
        )

        XCTAssertEqual(
            reports.count,
            21,
            "Twenty reports, then one notice that the rest were dropped."
        )
        XCTAssertEqual(
            reports.prefix(20).compactMap { $0["kind"] as? String },
            Array(repeating: "error", count: 20)
        )
        let notice = try XCTUnwrap(reports.last)
        XCTAssertEqual(notice["kind"] as? String, "suppressed")
        XCTAssertTrue(
            try XCTUnwrap(notice["message"] as? String)
                .contains("suppressed further reports")
        )
    }

    /// A hang throws nothing. Bitwarden's popup waits forever on a port reply
    /// while logging exactly why through `console.warn`, so the extension's
    /// own console output is the only trace that failure leaves — and it is
    /// verbose enough that a build has to ask for it.
    func testDiagnosticsChannelForwardsConsoleOutputOnlyWhenEnabled()
        async throws
    {
        let fileManager = FileManager.default
        let captured = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-console-test",
            enablesConsoleCapture: true
        )
        defer { try? fileManager.removeItem(at: captured.root) }
        let uncaptured = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-diagnostics-console-disabled-test"
        )
        defer { try? fileManager.removeItem(at: uncaptured.root) }

        let trigger = """
            console.warn("captured console warning");
            """
        let capturedReports = try await evaluatedDiagnosticsReports(
            source: captured.source,
            trigger: trigger
        )
        let uncapturedReports = try await evaluatedDiagnosticsReports(
            source: uncaptured.source,
            trigger: trigger
        )

        let consoleReports = capturedReports.filter {
            ($0["message"] as? String) == "captured console warning"
        }
        XCTAssertEqual(consoleReports.count, 1)
        let report = try XCTUnwrap(consoleReports.first)
        XCTAssertEqual(report["kind"] as? String, "console")
        XCTAssertEqual(report["level"] as? String, "warn")
        XCTAssertEqual(report["source"] as? String, "about:blank")
        XCTAssertTrue(
            uncapturedReports.isEmpty,
            "A build without console capture forwards no console output."
        )
        XCTAssertTrue(
            captured.source.contains(
                "const capturesExtensionConsole = true;"
            )
        )
        XCTAssertTrue(
            uncaptured.source.contains(
                "const capturesExtensionConsole = false;"
            ),
            """
            The disabled runtime carries the disabling literal, so the
            content-addressed filename differs between the two builds.
            """
        )
    }

    /// A native root that records who called its messaging entry points and
    /// with which receiver, so a wrapper that changed either is visible.
    private static let diagnosticsTraceFixtureNativeRoot = """
        globalThis.brokerRequests = [];
        globalThis.messagingCalls = [];
        const nativeRuntime = {
            id: "fixture-extension-id",
            getURL(path = "") { return "about:blank#" + path; },
            getManifest() { return { manifest_version: 3 }; },
            sendNativeMessage(host, message) {
                globalThis.brokerRequests.push({ host, message });
                return Promise.resolve({ recorded: true });
            },
            sendMessage(...args) {
                globalThis.messagingCalls.push({
                    op: "sendMessage",
                    receiverIsRuntime: this === nativeRuntime,
                    argumentCount: args.length
                });
                return Promise.resolve("native-reply");
            },
            connect(connectInfo) {
                globalThis.messagingCalls.push({
                    op: "connect",
                    receiverIsRuntime: this === nativeRuntime
                });
                return { name: connectInfo?.name, native: true };
            }
        };
        globalThis.nativeSendMessage = nativeRuntime.sendMessage;
        Object.defineProperty(globalThis, "chrome", {
            configurable: true,
            value: { runtime: nativeRuntime }
        });
        globalThis.diagnosticsReports = () => globalThis.brokerRequests
            .filter((entry) => entry.message?.api === "diagnostics.report")
            .map((entry) => entry.message);
        """

    private func evaluatedTraceFixtureResult(
        source: String
    ) async throws -> [String: Any] {
        let evaluatedResult = try await WKWebView().callAsyncJavaScript(
            """
            \(Self.diagnosticsTraceFixtureNativeRoot)
            \(source)
            const reply = await chrome.runtime.sendMessage({
                command: "fullSync",
                token: "secret-vault-token"
            });
            const port = chrome.runtime.connect({ name: "bw-popup" });
            await new Promise((resolve) => setTimeout(resolve, 60));
            return JSON.stringify({
                reply,
                portName: port?.name,
                portIsNative: port?.native === true,
                calls: globalThis.messagingCalls,
                reports: globalThis.diagnosticsReports(),
                wrapsSendMessage:
                    chrome.runtime.sendMessage
                        !== globalThis.nativeSendMessage
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        return try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(evaluatedResult as? String).utf8)
            ) as? [String: Any]
        )
    }

    /// Bitwarden's popup unlocks, sends `fullSync`, and waits for a
    /// `syncCompleted` broadcast the worker sends back the same way. Neither
    /// side logged anything, so which half of that exchange never happened
    /// was unanswerable — the trace answers it, and must do so without
    /// changing what either half means.
    func testMessageTraceReportsSendsWithoutChangingTheirContract()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-message-trace-test",
            enablesConsoleCapture: true
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let result = try await evaluatedTraceFixtureResult(
            source: fixture.source
        )

        // The contract first: the native implementation runs, with the
        // original receiver, and its return value is handed back untouched.
        XCTAssertEqual(result["wrapsSendMessage"] as? Bool, true)
        XCTAssertEqual(result["reply"] as? String, "native-reply")
        XCTAssertEqual(result["portName"] as? String, "bw-popup")
        XCTAssertEqual(result["portIsNative"] as? Bool, true)
        let calls = try XCTUnwrap(result["calls"] as? [[String: Any]])
        XCTAssertEqual(
            calls.map { $0["op"] as? String },
            ["sendMessage", "connect"]
        )
        XCTAssertTrue(
            calls.allSatisfy { $0["receiverIsRuntime"] as? Bool == true },
            "The receiver must reach the native function verbatim."
        )
        XCTAssertEqual(calls.first?["argumentCount"] as? Int, 1)

        let traces = try XCTUnwrap(result["reports"] as? [[String: Any]])
            .filter { $0["kind"] as? String == "trace" }
        XCTAssertEqual(
            traces.map { $0["op"] as? String },
            ["sendMessage", "sendMessageResolved", "connect"],
            """
            A send is traced as it happens and again when its promise \
            settles — the observer is attached before the caller's own \
            continuation, so it runs first — while a `connect` returns a \
            port rather than a promise and settles nothing.
            """
        )
        let sendTrace = try XCTUnwrap(traces.first?["message"] as? String)
        XCTAssertTrue(sendTrace.contains("command=fullSync"), sendTrace)
        XCTAssertTrue(sendTrace.contains("keys:[command,token]"), sendTrace)
        XCTAssertFalse(
            sendTrace.contains("secret-vault-token"),
            """
            A trace records the command and the message's shape, never its \
            values: this is a password manager's traffic. Observed: \
            \(sendTrace)
            """
        )
        XCTAssertTrue(
            try XCTUnwrap(traces[2]["message"] as? String)
                .contains("bw-popup"),
            "A connect trace names the port."
        )
    }

    /// The trace rides the console-capture gate, and a build without it must
    /// not carry so much as a wrapper: `runtime.sendMessage` stays the object
    /// WebKit installed.
    func testMessageTraceIsAbsentWithoutConsoleCapture() async throws {
        let fileManager = FileManager.default
        let fixture = try diagnosticsFixtureCompatibilityRuntime(
            named: "crest-webextension-message-trace-disabled-test"
        )
        defer { try? fileManager.removeItem(at: fixture.root) }

        let result = try await evaluatedTraceFixtureResult(
            source: fixture.source
        )

        XCTAssertEqual(
            result["wrapsSendMessage"] as? Bool,
            false,
            "A gated-off build replaces no messaging entry point."
        )
        XCTAssertEqual(result["reply"] as? String, "native-reply")
        XCTAssertEqual(
            try XCTUnwrap(result["reports"] as? [[String: Any]]).count,
            0
        )
    }

    /// Reads the JSON object a `const <name> = Object.freeze({...});`
    /// declaration publishes into the generated runtime.
    private static func generatedJSONLiteral(
        named name: String,
        in source: String
    ) -> String? {
        guard
            let declaration = source.range(
                of: "const \(name) = Object.freeze("
            ),
            let open = source[declaration.upperBound...].firstIndex(of: "{")
        else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
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

/// Serves one document for every request on the extension's scheme.
///
/// `ChromeWebStoreTestSchemeHandler` answers with an empty document, which is
/// all the runtime-identity test needs. A diagnostics test needs the page's
/// own inline scripts to be the ones that throw, so it supplies the body.
private final class ChromeWebStoreDocumentSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    private let html: String

    init(html: String) {
        self.html = html
        super.init()
    }

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
        urlSchemeTask.didReceive(Data(html.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask: any WKURLSchemeTask
    ) {}
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
