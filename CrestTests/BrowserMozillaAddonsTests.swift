import CryptoKit
import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMozillaAddonsTests: XCTestCase {
    private let darkReaderSlug = "darkreader"
    private let darkReaderGUID = "addon@darkreader.org"

    // MARK: - Identity

    func testGeckoIdentityAcceptsMozillasTwoShapesAndRejectsOthers() {
        XCTAssertEqual(
            BrowserMozillaExtensionID(darkReaderGUID)?.rawValue,
            darkReaderGUID
        )
        XCTAssertEqual(
            BrowserMozillaExtensionID(
                "{446900e4-71c2-419f-a6a7-df9c091e268b}"
            )?.rawValue,
            "{446900e4-71c2-419f-a6a7-df9c091e268b}"
        )
        XCTAssertEqual(
            BrowserMozillaExtensionID("uBlock0@raymondhill.net")?.rawValue,
            "uBlock0@raymondhill.net"
        )

        XCTAssertNil(BrowserMozillaExtensionID(""))
        XCTAssertNil(BrowserMozillaExtensionID("no-at-sign-or-braces"))
        XCTAssertNil(BrowserMozillaExtensionID("{not-a-uuid}"))
        XCTAssertNil(BrowserMozillaExtensionID("two@at@signs.test"))
        XCTAssertNil(BrowserMozillaExtensionID("trailing@"))
        XCTAssertNil(BrowserMozillaExtensionID("space in@id.test"))
        XCTAssertNil(BrowserMozillaExtensionID("path/traversal@id.test"))
        XCTAssertNil(
            BrowserMozillaExtensionID(
                String(repeating: "a", count: 250) + "@id.test"
            )
        )
    }

    func testGeckoIdentityStripsPunctuationFromItsPackageNameComponent()
        throws
    {
        let email = try XCTUnwrap(BrowserMozillaExtensionID(darkReaderGUID))
        let braced = try XCTUnwrap(
            BrowserMozillaExtensionID(
                "{446900e4-71c2-419f-a6a7-df9c091e268b}"
            )
        )

        XCTAssertEqual(email.packageNameComponent, "addon-darkreader.org")
        XCTAssertEqual(
            braced.packageNameComponent,
            "-446900e4-71c2-419f-a6a7-df9c091e268b-"
        )
        for component in [email, braced].map(\.packageNameComponent) {
            XCTAssertFalse(component.contains("/"))
            XCTAssertFalse(component.contains("@"))
            XCTAssertEqual(
                URL(fileURLWithPath: component).lastPathComponent,
                component
            )
        }
    }

    func testAddonSlugRejectsPathAndQueryPunctuation() {
        XCTAssertEqual(
            BrowserMozillaAddonSlug("ublock-origin")?.rawValue,
            "ublock-origin"
        )
        XCTAssertNil(BrowserMozillaAddonSlug(""))
        XCTAssertNil(BrowserMozillaAddonSlug("../escape"))
        XCTAssertNil(BrowserMozillaAddonSlug("slug/with/slash"))
        XCTAssertNil(BrowserMozillaAddonSlug("slug?query=1"))
        XCTAssertNil(BrowserMozillaAddonSlug("slug with space"))
        XCTAssertNil(
            BrowserMozillaAddonSlug(String(repeating: "a", count: 101))
        )
    }

    // MARK: - Detail page recognition

    func testAddonItemRecognizesDarkReaderAndRejectsUntrustedLookalikes()
        throws
    {
        let item = try XCTUnwrap(
            BrowserMozillaAddonsItem(
                url: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/"
                )!
            )
        )

        XCTAssertEqual(item.slug.rawValue, darkReaderSlug)
        XCTAssertEqual(item.locale, "en-US")
        XCTAssertEqual(item.application, "firefox")
        XCTAssertEqual(
            item.storeURL.absoluteString,
            "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/"
        )

        XCTAssertNotNil(
            BrowserMozillaAddonsItem(
                url: URL(
                    string:
                        "https://addons.mozilla.org/de/firefox/addon/\(darkReaderSlug)/"
                )!
            )
        )
        XCTAssertNotNil(
            BrowserMozillaAddonsItem(
                url: URL(
                    string:
                        "https://addons.mozilla.org/pt-BR/android/addon/\(darkReaderSlug)/"
                )!
            )
        )

        for rejected in [
            "http://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/",
            "https://addons.mozilla.org.evil.test/en-US/firefox/addon/\(darkReaderSlug)/",
            "https://evil.test/en-US/firefox/addon/\(darkReaderSlug)/",
            "https://addons.mozilla.org:8443/en-US/firefox/addon/\(darkReaderSlug)/",
            "https://addons.mozilla.org/firefox/addon/\(darkReaderSlug)/",
            "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/versions/",
            "https://addons.mozilla.org/en-US/thunderbird/addon/\(darkReaderSlug)/",
            "https://addons.mozilla.org/en-US/firefox/search/?q=dark",
        ] {
            XCTAssertNil(
                BrowserMozillaAddonsItem(url: URL(string: rejected)!),
                "\(rejected) must not resolve to an add-on detail page."
            )
        }
    }

    // MARK: - Install navigation

    func testInstallNavigationRequiresTheCurrentTrustedAddonPage() throws {
        let item = try XCTUnwrap(
            BrowserMozillaAddonsItem(
                url: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/"
                )!
            )
        )
        let navigationURL = BrowserMozillaAddonsInstallNavigation.url(
            for: item.slug
        )

        XCTAssertEqual(
            navigationURL.absoluteString,
            "crest-extension-install://mozilla-addons/\(darkReaderSlug)"
        )
        XCTAssertEqual(
            BrowserMozillaAddonsInstallNavigation.item(
                for: navigationURL,
                currentURL: item.storeURL
            ),
            item
        )

        // A different add-on than the page being displayed.
        XCTAssertNil(
            BrowserMozillaAddonsInstallNavigation.item(
                for: BrowserMozillaAddonsInstallNavigation.url(
                    for: try XCTUnwrap(
                        BrowserMozillaAddonSlug("ublock-origin")
                    )
                ),
                currentURL: item.storeURL
            )
        )
        // A lookalike host in the address bar.
        XCTAssertNil(
            BrowserMozillaAddonsInstallNavigation.item(
                for: navigationURL,
                currentURL: URL(
                    string:
                        "https://addons.mozilla.org.evil.test/en-US/firefox/addon/\(darkReaderSlug)/"
                )!
            )
        )
        // Not an add-on detail page at all.
        XCTAssertNil(
            BrowserMozillaAddonsInstallNavigation.item(
                for: navigationURL,
                currentURL: URL(
                    string: "https://addons.mozilla.org/en-US/firefox/"
                )!
            )
        )
        for rejected in [
            "crest-extension-install://mozilla-addons/\(darkReaderSlug)?x=1",
            "crest-extension-install://mozilla-addons/\(darkReaderSlug)#x",
            "crest-extension-install://mozilla-addons/a/\(darkReaderSlug)",
            "crest-extension-install://chrome-web-store/\(darkReaderSlug)",
            "https://addons.mozilla.org/\(darkReaderSlug)",
        ] {
            XCTAssertNil(
                BrowserMozillaAddonsInstallNavigation.item(
                    for: URL(string: rejected)!,
                    currentURL: item.storeURL
                ),
                "\(rejected) must not authorize an installation."
            )
        }
    }

    func testContentBridgeAdvertisesCrestOnlyOnTheTrustedStore() {
        let source = BrowserMozillaAddonsContentBridge.source

        XCTAssertTrue(source.contains("Add to Crest"))
        XCTAssertTrue(source.contains("addons.mozilla.org"))
        XCTAssertTrue(
            source.contains(BrowserMozillaAddonsInstallNavigation.scheme)
        )
        // AMO serves a different install component to a non-Firefox user
        // agent, so the mount point must be the wrapper both branches share.
        XCTAssertTrue(
            source.contains(".Addon-install > .InstallButtonWrapper")
        )
        XCTAssertFalse(source.contains("AMInstallButton"))
        // Themes reuse the identical install markup.
        XCTAssertTrue(source.contains("Addon-extension"))
    }

    // MARK: - Listing decoding

    func testListingDecoderReadsTheCurrentAddonsAPIShape() throws {
        let listing = try BrowserMozillaAddonsListingDecoder.listing(
            from: listingPayload()
        )

        XCTAssertEqual(listing.slug.rawValue, darkReaderSlug)
        XCTAssertEqual(listing.extensionID.rawValue, darkReaderGUID)
        XCTAssertEqual(listing.displayName, "Dark Reader")
        XCTAssertEqual(listing.summary, "Dark mode for every website.")
        XCTAssertEqual(listing.version, "4.9.129")
        XCTAssertEqual(
            listing.downloadURL.absoluteString,
            "https://addons.mozilla.org/firefox/downloads/file/4899461/darkreader-4.9.129.xpi"
        )
        XCTAssertEqual(listing.xpiSHA256Hex, String(repeating: "f", count: 64))
        XCTAssertEqual(listing.byteCount, 856_583)
        XCTAssertTrue(listing.isMozillaRecommended)
    }

    func testListingDecoderRejectsUntrustedAndUnusableListings() throws {
        let notFound = Data(#"{"detail":"Not found."}"#.utf8)
        XCTAssertThrowsError(
            try BrowserMozillaAddonsListingDecoder.listing(from: notFound)
        ) { error in
            XCTAssertEqual(
                error as? BrowserMozillaAddonsListingError,
                .unknownAddon
            )
        }

        let expectations: [(String, Any, BrowserMozillaAddonsListingError)] = [
            ("type", "statictheme", .unsupportedAddonType),
            ("status", "incomplete", .unavailableAddon),
            ("is_disabled", true, .unavailableAddon),
            ("guid", "not a gecko id", .invalidExtensionID),
            ("slug", "../escape", .invalidSlug),
        ]
        for (key, value, expected) in expectations {
            let payload = try listingPayload(overriding: [key: value])
            XCTAssertThrowsError(
                try BrowserMozillaAddonsListingDecoder.listing(from: payload)
            ) { error in
                XCTAssertEqual(
                    error as? BrowserMozillaAddonsListingError,
                    expected,
                    "Overriding \(key) must be refused."
                )
            }
        }
    }

    func testListingDecoderRefusesADownloadOffMozillasHostOrWithoutADigest()
        throws
    {
        let offHost = try listingPayload(
            overridingFile: [
                "url": "https://cdn.evil.test/file/4899461/darkreader.xpi"
            ]
        )
        XCTAssertThrowsError(
            try BrowserMozillaAddonsListingDecoder.listing(from: offHost)
        ) { error in
            XCTAssertEqual(
                error as? BrowserMozillaAddonsListingError,
                .invalidDownloadURL
            )
        }

        let insecure = try listingPayload(
            overridingFile: [
                "url":
                    "http://addons.mozilla.org/firefox/downloads/file/1/a.xpi"
            ]
        )
        XCTAssertThrowsError(
            try BrowserMozillaAddonsListingDecoder.listing(from: insecure)
        ) { error in
            XCTAssertEqual(
                error as? BrowserMozillaAddonsListingError,
                .invalidDownloadURL
            )
        }

        for digest in ["md5:abc", "sha256:not-hex", String(repeating: "f", count: 64)] {
            let payload = try listingPayload(overridingFile: ["hash": digest])
            XCTAssertThrowsError(
                try BrowserMozillaAddonsListingDecoder.listing(from: payload)
            ) { error in
                XCTAssertEqual(
                    error as? BrowserMozillaAddonsListingError,
                    .unsupportedDigest,
                    "\(digest) is not a digest Crest can verify."
                )
            }
        }
    }

    // MARK: - Package verification

    func testVerifierAcceptsAMozillaSignedArchiveMatchingItsListing() throws {
        let fixture = try archiveFixture()

        let package = try BrowserXPIVerifier().verify(
            fixture.archiveData,
            expectedSHA256Hex: fixture.sha256Hex,
            expectedByteCount: fixture.archiveData.count,
            extensionID: fixture.extensionID
        )

        XCTAssertEqual(package.extensionID, fixture.extensionID)
        XCTAssertEqual(package.archiveData, fixture.archiveData)
        XCTAssertEqual(package.xpiSHA256Hex, fixture.sha256Hex)
    }

    func testVerifierRejectsATamperedOrMisdeclaredArchive() throws {
        let fixture = try archiveFixture()
        let verifier = BrowserXPIVerifier()

        XCTAssertThrowsError(
            try verifier.verify(
                fixture.archiveData,
                expectedSHA256Hex: String(repeating: "a", count: 64),
                expectedByteCount: fixture.archiveData.count,
                extensionID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(error as? BrowserXPIVerifierError, .digestMismatch)
        }

        XCTAssertThrowsError(
            try verifier.verify(
                fixture.archiveData,
                expectedSHA256Hex: fixture.sha256Hex,
                expectedByteCount: fixture.archiveData.count + 1,
                extensionID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserXPIVerifierError,
                .declaredSizeMismatch
            )
        }

        // A single flipped byte breaks the digest the listing published.
        var tampered = fixture.archiveData
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        XCTAssertThrowsError(
            try verifier.verify(
                tampered,
                expectedSHA256Hex: fixture.sha256Hex,
                expectedByteCount: tampered.count,
                extensionID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(error as? BrowserXPIVerifierError, .digestMismatch)
        }

        let notAnArchive = Data("this is not a zip".utf8)
        XCTAssertThrowsError(
            try verifier.verify(
                notAnArchive,
                expectedSHA256Hex: Data(SHA256.hash(data: notAnArchive))
                    .hexString,
                expectedByteCount: notAnArchive.count,
                extensionID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(error as? BrowserXPIVerifierError, .invalidArchive)
        }
    }

    func testVerifierRejectsAnArchiveMozillaNeverSigned() throws {
        let fixture = try archiveFixture(isMozillaSigned: false)

        XCTAssertThrowsError(
            try BrowserXPIVerifier().verify(
                fixture.archiveData,
                expectedSHA256Hex: fixture.sha256Hex,
                expectedByteCount: fixture.archiveData.count,
                extensionID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserXPIVerifierError,
                .missingMozillaSignature
            )
        }
    }

    func testVerifierRejectsAnArchiveWithoutAManifest() throws {
        let fixture = try archiveFixture(includesManifest: false)

        XCTAssertThrowsError(
            try BrowserXPIVerifier().verify(
                fixture.archiveData,
                expectedSHA256Hex: fixture.sha256Hex,
                expectedByteCount: fixture.archiveData.count,
                extensionID: fixture.extensionID
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserXPIVerifierError,
                .missingManifest
            )
        }
    }

    // MARK: - Provenance

    func testVerifiedArchiveStagesUnderTheGeckoIdentityInItsSpace() throws {
        let fixture = try archiveFixture()
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-mozilla-package-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: root
        )
        let spaceID = SpaceID()

        let staged = try store.stage(
            BrowserVerifiedXPIPackage(
                extensionID: fixture.extensionID,
                archiveData: fixture.archiveData,
                xpiSHA256Hex: fixture.sha256Hex
            ),
            in: spaceID
        )

        XCTAssertEqual(staged.extensionID, darkReaderGUID)
        XCTAssertEqual(staged.resourceURL.pathExtension, "zip")
        XCTAssertTrue(
            staged.packageName.hasPrefix("addon-darkreader.org-")
        )
        XCTAssertEqual(
            try Data(contentsOf: staged.resourceURL),
            fixture.archiveData
        )
        XCTAssertEqual(
            try store.resourceURL(
                packageName: staged.packageName,
                in: spaceID
            ),
            staged.resourceURL
        )
    }

    func testMozillaSourceRoundTripsAndRejectsProvenanceMismatch() throws {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let spaceID = SpaceID()
        let source = try mozillaSource()
        var record = installation(
            id: darkReaderGUID,
            spaceID: spaceID,
            source: .mozillaAddons(source)
        )

        XCTAssertTrue(registry.upsert(record))
        XCTAssertEqual(
            BrowserExtensionRegistry(persistence: persistence)
                .installation(extensionID: darkReaderGUID, in: spaceID),
            record
        )

        // The record's own identity must be the source's gecko identity.
        record = installation(
            id: "someone-else@example.test",
            spaceID: spaceID,
            source: .mozillaAddons(source)
        )
        XCTAssertFalse(registry.upsert(record))
    }

    func testRegistryRefusesASourceWhoseStoreURLOrDigestDoesNotHold() throws {
        let spaceID = SpaceID()
        let extensionID = try XCTUnwrap(
            BrowserMozillaExtensionID(darkReaderGUID)
        )
        let untrusted: [BrowserMozillaAddonsSource] = [
            // A store URL that names a different add-on than the source.
            BrowserMozillaAddonsSource(
                slug: try XCTUnwrap(BrowserMozillaAddonSlug(darkReaderSlug)),
                extensionID: extensionID,
                storeURL: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/"
                )!,
                version: "4.9.129",
                xpiSHA256Hex: String(repeating: "a", count: 64)
            ),
            // A store URL off Mozilla's host entirely.
            BrowserMozillaAddonsSource(
                slug: try XCTUnwrap(BrowserMozillaAddonSlug(darkReaderSlug)),
                extensionID: extensionID,
                storeURL: URL(
                    string:
                        "https://addons.mozilla.org.evil.test/en-US/firefox/addon/\(darkReaderSlug)/"
                )!,
                version: "4.9.129",
                xpiSHA256Hex: String(repeating: "a", count: 64)
            ),
            // A digest that is not a SHA-256.
            BrowserMozillaAddonsSource(
                slug: try XCTUnwrap(BrowserMozillaAddonSlug(darkReaderSlug)),
                extensionID: extensionID,
                storeURL: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/"
                )!,
                version: "4.9.129",
                xpiSHA256Hex: "abc"
            ),
            // A version string that could reach a file name.
            BrowserMozillaAddonsSource(
                slug: try XCTUnwrap(BrowserMozillaAddonSlug(darkReaderSlug)),
                extensionID: extensionID,
                storeURL: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/"
                )!,
                version: "../../etc/passwd",
                xpiSHA256Hex: String(repeating: "a", count: 64)
            ),
        ]

        for source in untrusted {
            let registry = BrowserExtensionRegistry(
                persistence: InMemoryBrowserExtensionRegistryPersistence()
            )
            XCTAssertFalse(
                registry.upsert(
                    installation(
                        id: darkReaderGUID,
                        spaceID: spaceID,
                        source: .mozillaAddons(source)
                    )
                ),
                "An unverifiable Firefox Add-ons record was persisted."
            )
        }
    }

    func testRuntimeIdentifierNamespacesEveryFirefoxAddonPerSpace() throws {
        let source = try mozillaSource()
        let spaceID = SpaceID()

        XCTAssertEqual(
            BrowserExtensionRuntimeIdentifierPolicy.identifier(
                extensionID: darkReaderGUID,
                source: .mozillaAddons(source),
                spaceID: spaceID
            ),
            "\(darkReaderGUID).space.\(spaceID.rawValue.uuidString.lowercased())"
        )
    }

    func testVerifiedFirefoxNativeMessagingCanUseThePlatformCompanionBridge() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging", "storage"],
            source: .mozillaAddons,
            nativeMessagingCapability: .available
        )

        XCTAssertTrue(assessment.canRun)
        XCTAssertTrue(assessment.issues.isEmpty)

        let unavailable = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging", "storage"],
            source: .mozillaAddons,
            nativeMessagingCapability: .unavailableInAppSandbox
        )
        XCTAssertFalse(unavailable.canRun)
        XCTAssertEqual(
            unavailable.blockingIssues.map(\.kind),
            [.nativeMessagingUnavailable]
        )

        let ordinary = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["storage", "tabs"],
            source: .mozillaAddons,
            nativeMessagingCapability: .unavailableInAppSandbox
        )
        XCTAssertTrue(ordinary.canRun)
        XCTAssertTrue(ordinary.issues.isEmpty)
    }

    func testVerifiedFirefoxPackageUsesTheSharedCompatibilityOverlay()
        throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-firefox-compatibility-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let resourceURL = root.appending(
            path: "addon",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: resourceURL,
            withIntermediateDirectories: true
        )
        try Data("globalThis.started = true;".utf8).write(
            to: resourceURL.appending(path: "background.js")
        )
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Firefox Compatibility Probe",
            "version": "1.0",
            "background": ["scripts": ["background.js"]],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: resourceURL.appending(path: "manifest.json")
        )
        let source = try mozillaSource()
        let storedInstallation = installation(
            id: source.extensionID.rawValue,
            spaceID: SpaceID(),
            source: .mozillaAddons(source),
            requestedPermissions: ["nativeMessaging", "privacy"]
        )

        let prepared = try BrowserStoreWebExtensionStoredResourcePreparer(
            fileManager: fileManager
        ).prepare(
            resourceURL: resourceURL,
            installation: storedInstallation
        )

        XCTAssertNotEqual(prepared.resourceURL, resourceURL)
        XCTAssertNotNil(prepared.retainedAccess)
        let preparedManifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: prepared.resourceURL.appending(
                        path: "manifest.json"
                    )
                )
            ) as? [String: Any]
        )
        let background = try XCTUnwrap(
            preparedManifest["background"] as? [String: Any]
        )
        let scripts = try XCTUnwrap(background["scripts"] as? [String])
        XCTAssertEqual(
            Array(scripts.prefix(2)),
            [
                "crest-webextension-background-marker.js",
                "crest-webextension-compatibility.js",
            ]
        )
    }

    func testFirefoxOnlyManifestKeysSurfaceAsWarningsRatherThanBlockers()
        async throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-firefox-manifest-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        // A Firefox-shaped MV2 package: persistent background page, gecko
        // settings, and a sidebar action WebKit does not implement.
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Firefox Manifest Probe",
            "version": "1.0",
            "browser_specific_settings": [
                "gecko": [
                    "id": darkReaderGUID,
                    "strict_min_version": "78.0",
                ]
            ],
            "background": [
                "scripts": ["background.js"],
                "persistent": true,
            ],
            "sidebar_action": [
                "default_panel": "sidebar.html",
                "default_title": "Probe",
            ],
            "permissions": ["storage", "contextualIdentities"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "manifest.json")
        )
        try Data("globalThis.started = true;".utf8).write(
            to: root.appending(path: "background.js")
        )
        try Data("<html></html>".utf8).write(
            to: root.appending(path: "sidebar.html")
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: root)

        XCTAssertEqual(webExtension.displayName, "Firefox Manifest Probe")
        XCTAssertEqual(webExtension.manifestVersion, 2)
        XCTAssertTrue(webExtension.hasBackgroundContent)
        // Whatever WebKit reports about Firefox-only keys is a warning the
        // review sheet shows, never a reason the package cannot be inspected.
        let settings = try XCTUnwrap(
            webExtension.manifest["browser_specific_settings"]
                as? [String: Any]
        )
        let gecko = try XCTUnwrap(settings["gecko"] as? [String: Any])
        XCTAssertEqual(gecko["id"] as? String, darkReaderGUID)
    }

    // MARK: - Install and rollback

    func testRejectedFirstInstallationRemovesProvisionalState() async throws {
        let fileManager = FileManager.default
        let fixture = try installationFixture()
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
        // The staged bytes hash to something other than what the source claims.
        let rejected = candidate(
            item: fixture.item,
            extensionID: fixture.extensionID,
            archiveData: fixture.archiveData,
            sourceDigest: String(repeating: "b", count: 64),
            packageDigest: String(repeating: "c", count: 64)
        )

        do {
            _ = try await pool.installMozillaAddonsExtension(
                rejected,
                in: space
            )
            XCTFail("An untrusted installation record was persisted.")
        } catch BrowserExtensionControllerPoolError
            .invalidInstallationRecord
        {
            // Identity is cross-checked before anything reaches the registry.
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
        let fixture = try installationFixture()
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
        let digest = String(repeating: "a", count: 64)
        let accepted = candidate(
            item: fixture.item,
            extensionID: fixture.extensionID,
            archiveData: fixture.archiveData,
            sourceDigest: digest,
            packageDigest: digest
        )

        _ = try await pool.installMozillaAddonsExtension(accepted, in: space)
        let originalPackageName = try XCTUnwrap(
            registry.installation(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )?.packageName
        )

        let rejected = candidate(
            item: fixture.item,
            extensionID: fixture.extensionID,
            archiveData: fixture.archiveData,
            sourceDigest: String(repeating: "b", count: 64),
            packageDigest: String(repeating: "c", count: 64)
        )
        do {
            _ = try await pool.installMozillaAddonsExtension(
                rejected,
                in: space
            )
            XCTFail("An untrusted replacement record was persisted.")
        } catch BrowserExtensionControllerPoolError
            .invalidInstallationRecord
        {
            // The previous installation must survive a refused replacement.
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

    func testInstalledFirefoxAddonReportsItsStoreAndNamespacedIdentity()
        async throws
    {
        let fileManager = FileManager.default
        let fixture = try installationFixture()
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
        let digest = String(repeating: "a", count: 64)

        let summary = try await pool.installMozillaAddonsExtension(
            candidate(
                item: fixture.item,
                extensionID: fixture.extensionID,
                archiveData: fixture.archiveData,
                sourceDigest: digest,
                packageDigest: digest
            ),
            in: space
        )

        XCTAssertEqual(summary.sourceDisplayName, "Firefox Add-ons")
        let context = try XCTUnwrap(
            pool.loadedContext(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )
        )
        XCTAssertEqual(
            context.uniqueIdentifier,
            "\(fixture.extensionID.rawValue).space."
                + space.id.rawValue.uuidString.lowercased()
        )
        guard
            case .mozillaAddons(let source) = registry.installation(
                extensionID: fixture.extensionID.rawValue,
                in: space.id
            )?.source
        else {
            return XCTFail(
                "The installation did not retain Firefox Add-ons provenance."
            )
        }
        XCTAssertEqual(source.extensionID, fixture.extensionID)
        XCTAssertEqual(source.slug, fixture.item.slug)
    }

    // MARK: - Live integration

    func testLiveFirefoxAddonVerifiesInspectsAndLoadsWhenEnabled()
        async throws
    {
        let integrationMarker = URL(
            filePath: "/tmp/CrestRunAMOIntegration"
        )
        guard
            ProcessInfo.processInfo.environment["CREST_RUN_AMO_INTEGRATION"]
                == "1"
                || FileManager.default.fileExists(
                    atPath: integrationMarker.path
                )
        else {
            throw XCTSkip(
                "Set CREST_RUN_AMO_INTEGRATION=1 to verify current Firefox Add-ons packages."
            )
        }

        let addons = [
            ("Dark Reader", darkReaderSlug),
            ("uBlock Origin", "ublock-origin"),
            ("Bitwarden", "bitwarden-password-manager"),
        ]
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-amo-live-test-\(UUID().uuidString)",
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
        let space = BrowserSession.preview.spaces[0]
        let provider = BrowserMozillaAddonsProvider()

        for (name, slug) in addons {
            let item = try XCTUnwrap(
                BrowserMozillaAddonsItem(
                    url: URL(
                        string:
                            "https://addons.mozilla.org/en-US/firefox/addon/\(slug)/"
                    )!
                )
            )
            let candidate = try await provider.candidate(for: item)
            XCTAssertEqual(candidate.source.slug.rawValue, slug)
            XCTAssertFalse(candidate.source.xpiSHA256Hex.isEmpty)

            guard candidate.compatibility.canRun else {
                print(
                    "CREST_AMO_AUDIT|\(name)|\(candidate.version ?? "unknown")|blocked|reason=\(candidate.compatibility.blockingIssues.map(\.message).joined(separator: ";"))"
                )
                continue
            }
            let summary = try await pool.installMozillaAddonsExtension(
                candidate,
                in: space
            )
            try await Task.sleep(for: .milliseconds(350))
            let context = try XCTUnwrap(
                pool.loadedContext(
                    extensionID: candidate.source.extensionID.rawValue,
                    in: space.id
                )
            )
            XCTAssertTrue(summary.isLoaded)
            XCTAssertTrue(context.isLoaded)
            print(
                "CREST_AMO_AUDIT|\(name)|\(candidate.version ?? "unknown")|loaded|permissions=\(candidate.requestedPermissions.joined(separator: ","))|manifestErrors=\(candidate.errors.joined(separator: ";"))|runtimeErrors=\(context.errors.map(\.localizedDescription).joined(separator: ";"))|unsupported=\(context.unsupportedAPIs.sorted().joined(separator: ","))"
            )
            try await pool.removeExtension(
                extensionID: candidate.source.extensionID.rawValue,
                from: space
            )
        }
    }

    // MARK: - Fixtures

    private func mozillaSource() throws -> BrowserMozillaAddonsSource {
        BrowserMozillaAddonsSource(
            slug: try XCTUnwrap(BrowserMozillaAddonSlug(darkReaderSlug)),
            extensionID: try XCTUnwrap(
                BrowserMozillaExtensionID(darkReaderGUID)
            ),
            storeURL: URL(
                string:
                    "https://addons.mozilla.org/en-US/firefox/addon/\(darkReaderSlug)/"
            )!,
            version: "4.9.129",
            xpiSHA256Hex: String(repeating: "a", count: 64)
        )
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
            packageName: "addon-darkreader.org-probe.zip",
            source: source,
            displayName: "Dark Reader",
            version: "4.9.129",
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

    private func candidate(
        item: BrowserMozillaAddonsItem,
        extensionID: BrowserMozillaExtensionID,
        archiveData: Data,
        sourceDigest: String,
        packageDigest: String
    ) -> BrowserMozillaAddonsCandidate {
        BrowserMozillaAddonsCandidate(
            item: item,
            source: BrowserMozillaAddonsSource(
                slug: item.slug,
                extensionID: extensionID,
                storeURL: item.storeURL,
                version: "1.0",
                xpiSHA256Hex: sourceDigest
            ),
            verifiedPackage: BrowserVerifiedXPIPackage(
                extensionID: extensionID,
                archiveData: archiveData,
                xpiSHA256Hex: packageDigest
            ),
            displayName: "Rollback Probe",
            version: "1.0",
            displayDescription: nil,
            requestedPermissions: [],
            requestedHosts: [],
            errors: [],
            iconPayload: nil,
            hasOptionsPage: false,
            hasCommands: false,
            isMozillaRecommended: false,
            nativeMessagingCapability: .available
        )
    }

    private func installationFixture() throws -> (
        rootURL: URL,
        packageRootURL: URL,
        archiveData: Data,
        extensionID: BrowserMozillaExtensionID,
        item: BrowserMozillaAddonsItem
    ) {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-mozilla-rollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = rootURL.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        let archiveURL = rootURL.appending(path: "addon.zip")
        let packageRootURL = rootURL.appending(
            path: "Packages",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Rollback Probe",
            "version": "1.0",
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: sourceURL.appending(path: "manifest.json")
        )
        try createZipArchive(from: sourceURL, at: archiveURL)
        let extensionID = try XCTUnwrap(
            BrowserMozillaExtensionID("rollback-probe@crest.test")
        )
        let item = try XCTUnwrap(
            BrowserMozillaAddonsItem(
                url: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/rollback-probe/"
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

    /// Builds a real ZIP whose entry names reproduce a Mozilla-signed XPI.
    private func archiveFixture(
        includesManifest: Bool = true,
        isMozillaSigned: Bool = true
    ) throws -> ArchiveFixture {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-xpi-fixture-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let sourceURL = root.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        let metaInfURL = sourceURL.appending(
            path: "META-INF",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: metaInfURL,
            withIntermediateDirectories: true
        )
        if includesManifest {
            try JSONSerialization.data(
                withJSONObject: [
                    "manifest_version": 2,
                    "name": "Dark Reader",
                    "version": "4.9.129",
                ] as [String: Any]
            ).write(to: sourceURL.appending(path: "manifest.json"))
        } else {
            try Data("placeholder".utf8).write(
                to: sourceURL.appending(path: "readme.txt")
            )
        }
        if isMozillaSigned {
            try Data("Manifest-Version: 1.0\n".utf8).write(
                to: metaInfURL.appending(path: "manifest.mf")
            )
            try Data("Signature-Version: 1.0\n".utf8).write(
                to: metaInfURL.appending(path: "mozilla.sf")
            )
            try Data([0x30, 0x82, 0x01, 0x00]).write(
                to: metaInfURL.appending(path: "mozilla.rsa")
            )
        } else {
            try Data("Manifest-Version: 1.0\n".utf8).write(
                to: metaInfURL.appending(path: "manifest.mf")
            )
        }
        let archiveURL = root.appending(path: "addon.zip")
        try createZipArchive(from: sourceURL, at: archiveURL)
        let archiveData = try Data(contentsOf: archiveURL)
        return ArchiveFixture(
            extensionID: try XCTUnwrap(
                BrowserMozillaExtensionID(darkReaderGUID)
            ),
            archiveData: archiveData,
            sha256Hex: Data(SHA256.hash(data: archiveData)).hexString
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
            "--norsrc",
            "--noextattr",
            sourceURL.path,
            archiveURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func listingPayload(
        overriding overrides: [String: Any] = [:],
        overridingFile fileOverrides: [String: Any] = [:]
    ) throws -> Data {
        var file: [String: Any] = [
            "id": 4_899_461,
            "url":
                "https://addons.mozilla.org/firefox/downloads/file/4899461/darkreader-4.9.129.xpi",
            "hash": "sha256:\(String(repeating: "f", count: 64))",
            "size": 856_583,
            "status": "public",
        ]
        file.merge(fileOverrides) { _, new in new }
        var payload: [String: Any] = [
            "id": 855_413,
            "slug": darkReaderSlug,
            "guid": darkReaderGUID,
            "type": "extension",
            "status": "public",
            "is_disabled": false,
            "name": ["en-US": "Dark Reader"],
            "summary": ["en-US": "Dark mode for every website."],
            "promoted": [
                ["apps": ["firefox", "android"], "category": "recommended"]
            ],
            "current_version": [
                "id": 6_355_266,
                "version": "4.9.129",
                "file": file,
            ],
        ]
        payload.merge(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private struct ArchiveFixture {
        let extensionID: BrowserMozillaExtensionID
        let archiveData: Data
        let sha256Hex: String
    }
}
