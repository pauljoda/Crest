import Foundation
import XCTest

@testable import Crest

final class BrowserSafariWebExtensionAppLocatorTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserSafariWebExtensionAppLocatorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    func testLocatesOnlySafariWebExtensionsInsideAnApplication() throws {
        let applicationURL = try makeApplication(
            name: "Example",
            bundleIdentifier: "com.example.host",
            extensions: [
                ExtensionFixture(
                    name: "Example Web Extension",
                    bundleIdentifier: "com.example.host.web-extension",
                    extensionPointIdentifier: "com.apple.Safari.web-extension",
                    version: "2.4"
                ),
                ExtensionFixture(
                    name: "Example Blocker",
                    bundleIdentifier: "com.example.host.content-blocker",
                    extensionPointIdentifier: "com.apple.Safari.content-blocker",
                    version: "2.4"
                ),
                ExtensionFixture(
                    name: "Example App Extension",
                    bundleIdentifier: "com.example.host.safari-extension",
                    extensionPointIdentifier: "com.apple.Safari.extension",
                    version: "2.4"
                ),
            ]
        )

        let descriptors = try BrowserSafariWebExtensionAppLocator()
            .locate(in: applicationURL)

        XCTAssertEqual(descriptors.count, 1)
        let descriptor = try XCTUnwrap(descriptors.first)
        XCTAssertEqual(descriptor.applicationURL, applicationURL)
        XCTAssertEqual(descriptor.applicationDisplayName, "Example")
        XCTAssertEqual(
            descriptor.applicationBundleIdentifier,
            "com.example.host"
        )
        XCTAssertEqual(descriptor.displayName, "Example Web Extension")
        XCTAssertEqual(
            descriptor.extensionBundleIdentifier,
            "com.example.host.web-extension"
        )
        XCTAssertEqual(descriptor.version, "2.4")
        XCTAssertEqual(
            descriptor.relativeBundlePath,
            "Contents/PlugIns/Example Web Extension.appex"
        )
    }

    func testRejectsAFileThatIsNotAnApplicationBundle() throws {
        let textURL = temporaryDirectoryURL.appendingPathComponent("notes.txt")
        try Data("not an app".utf8).write(to: textURL)

        XCTAssertThrowsError(
            try BrowserSafariWebExtensionAppLocator().locate(in: textURL)
        ) { error in
            XCTAssertEqual(
                error as? BrowserSafariWebExtensionAppLocatorError,
                .invalidApplication
            )
        }
    }

    func testApplicationScannerFindsCompatibleAppsRecursivelyAndSortsThem()
        throws
    {
        let applicationsURL =
            temporaryDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
        let nestedURL =
            applicationsURL
            .appendingPathComponent("Setapp", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nestedURL,
            withIntermediateDirectories: true
        )
        _ = try makeApplication(
            name: "Zulu",
            bundleIdentifier: "com.example.zulu",
            extensions: [
                ExtensionFixture(
                    name: "Zulu Web Extension",
                    bundleIdentifier: "com.example.zulu.web-extension",
                    extensionPointIdentifier: "com.apple.Safari.web-extension",
                    version: "1.0"
                )
            ],
            directory: applicationsURL
        )
        _ = try makeApplication(
            name: "Alpha",
            bundleIdentifier: "com.example.alpha",
            extensions: [
                ExtensionFixture(
                    name: "Alpha Web Extension",
                    bundleIdentifier: "com.example.alpha.web-extension",
                    extensionPointIdentifier: "com.apple.Safari.web-extension",
                    version: "1.0"
                )
            ],
            directory: nestedURL
        )
        _ = try makeApplication(
            name: "Blocker Only",
            bundleIdentifier: "com.example.blocker",
            extensions: [
                ExtensionFixture(
                    name: "Blocker",
                    bundleIdentifier: "com.example.blocker.content-blocker",
                    extensionPointIdentifier: "com.apple.Safari.content-blocker",
                    version: "1.0"
                )
            ],
            directory: applicationsURL
        )

        let matches = BrowserSafariWebExtensionApplicationScanner()
            .scan(searchRoots: [applicationsURL])

        XCTAssertEqual(matches.map(\.applicationDisplayName), ["Alpha", "Zulu"])
        XCTAssertEqual(
            matches.map(\.applicationURL.lastPathComponent),
            ["Alpha.app", "Zulu.app"]
        )
    }

    func testApplicationScannerDeduplicatesOverlappingSearchRoots() throws {
        let applicationsURL =
            temporaryDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
        let applicationURL = try makeApplication(
            name: "Example",
            bundleIdentifier: "com.example.host",
            extensions: [
                ExtensionFixture(
                    name: "Example Web Extension",
                    bundleIdentifier: "com.example.host.web-extension",
                    extensionPointIdentifier: "com.apple.Safari.web-extension",
                    version: "1.0"
                )
            ],
            directory: applicationsURL
        )

        let matches = BrowserSafariWebExtensionApplicationScanner()
            .scan(searchRoots: [applicationsURL, applicationURL])

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.applicationURL, applicationURL)
    }

    func testSafariCustomScannerSnapshotsOnlyManifestDirectories() throws {
        let rootURL =
            temporaryDirectoryURL
            .appendingPathComponent("MagicExtensions", isDirectory: true)
        let extensionURL = rootURL.appendingPathComponent(
            "OblivionPortalGlow-F5B5",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        try Data(
            #"{"manifest_version":3,"name":"Oblivion Portal Glow","version":"1.0"}"#
                .utf8
        ).write(to: extensionURL.appendingPathComponent("manifest.json"))
        try Data("body { box-shadow: 0 0 24px red; }".utf8).write(
            to: extensionURL.appendingPathComponent("glow.css")
        )
        try Data("private database".utf8).write(
            to: rootURL.appendingPathComponent("Extensions.db")
        )

        let result = try BrowserSafariCustomExtensionScanner()
            .scan(searchRoot: rootURL)

        XCTAssertEqual(result.rejectedExtensionCount, 0)
        XCTAssertEqual(result.packages.count, 1)
        let package = try XCTUnwrap(result.packages.first)
        XCTAssertEqual(
            package.extensionID,
            "com.apple.Safari.MagicExtensions.OblivionPortalGlow-F5B5"
        )
        XCTAssertEqual(package.format, .safariCustom)
        XCTAssertEqual(
            package.directoryFiles.map(\.relativePath),
            ["glow.css", "manifest.json"]
        )
    }

    func testSafariCustomScannerRejectsSymbolicLinksWithoutDroppingSiblings()
        throws
    {
        let rootURL =
            temporaryDirectoryURL
            .appendingPathComponent("MagicExtensions", isDirectory: true)
        for name in ["Safe-1234", "Linked-5678"] {
            let extensionURL = rootURL.appendingPathComponent(
                name,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: extensionURL,
                withIntermediateDirectories: true
            )
            try Data(
                #"{"manifest_version":3,"name":"Fixture","version":"1.0"}"#
                    .utf8
            ).write(to: extensionURL.appendingPathComponent("manifest.json"))
        }
        try FileManager.default.createSymbolicLink(
            at:
                rootURL
                .appendingPathComponent("Linked-5678")
                .appendingPathComponent("outside"),
            withDestinationURL: temporaryDirectoryURL
        )

        let result = try BrowserSafariCustomExtensionScanner()
            .scan(searchRoot: rootURL)

        XCTAssertEqual(
            result.packages.map(\.extensionID),
            [
                "com.apple.Safari.MagicExtensions.Safe-1234"
            ])
        XCTAssertEqual(result.rejectedExtensionCount, 1)
    }

    @MainActor
    func testSafariCustomExtensionIsReviewedAndInstalledFromItsSnapshot()
        async throws
    {
        let rootURL =
            temporaryDirectoryURL
            .appendingPathComponent("MagicExtensions", isDirectory: true)
        let extensionURL = rootURL.appendingPathComponent(
            "OblivionPortalGlow-F5B5",
            isDirectory: true
        )
        let packageRootURL = temporaryDirectoryURL.appendingPathComponent(
            "CrestPackages",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        try Data(
            #"{"manifest_version":3,"name":"Oblivion Portal Glow","version":"1.0","description":"Adds a red glow.","content_scripts":[{"matches":["https://www.reddit.com/*"],"css":["glow.css"]}]}"#
                .utf8
        ).write(to: extensionURL.appendingPathComponent("manifest.json"))
        try Data("body { box-shadow: 0 0 24px red; }".utf8).write(
            to: extensionURL.appendingPathComponent("glow.css")
        )
        let scanResult = try BrowserSafariCustomExtensionScanner()
            .scan(searchRoot: rootURL)
        let package = try XCTUnwrap(scanResult.packages.first)

        try FileManager.default.removeItem(at: rootURL)

        let candidate = try await BrowserSafariCustomExtensionProvider(
            fileManager: .default,
            nativeMessagingCapability: .available
        ).candidate(for: package)
        XCTAssertEqual(candidate.displayName, "Oblivion Portal Glow")
        XCTAssertEqual(candidate.format, .safariCustom)
        XCTAssertEqual(
            candidate.requestedHosts,
            ["https://www.reddit.com/*"]
        )

        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: .default,
                rootURL: packageRootURL,
                removesRootOnDeinit: false
            ),
            registry: registry
        )
        let space = BrowserSession.preview.spaces[0]
        let summary = try await pool.installLocalExtension(
            candidate,
            in: space
        )
        let installation = try XCTUnwrap(
            registry.installation(extensionID: candidate.id, in: space.id)
        )

        XCTAssertEqual(summary.sourceDisplayName, "Safari Custom Extension")
        XCTAssertEqual(installation.source, .localPackage(candidate.source))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath:
                    packageRootURL
                    .appendingPathComponent(
                        space.id.rawValue.uuidString.lowercased(),
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        installation.packageName,
                        isDirectory: true
                    )
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
    }

    @MainActor
    func testSafariCustomExtensionReviewRejectsTraversal() async throws {
        let package = BrowserLocalExtensionPackage(
            extensionID: "com.apple.Safari.MagicExtensions.Invalid-1234",
            format: .safariCustom,
            directoryFiles: [
                BrowserLocalExtensionDirectoryFile(
                    relativePath: "manifest.json",
                    data: Data(
                        #"{"manifest_version":3,"name":"Invalid","version":"1.0"}"#
                            .utf8
                    )
                ),
                BrowserLocalExtensionDirectoryFile(
                    relativePath: "../outside.js",
                    data: Data("nope".utf8)
                ),
            ]
        )

        do {
            _ = try await BrowserSafariCustomExtensionProvider()
                .candidate(for: package)
            XCTFail("Expected the unsafe snapshot to be rejected")
        } catch is BrowserSafariCustomExtensionProviderError {
            // Expected: review never reconstructs a path outside its sandbox.
        }
    }

    @MainActor
    func testSignedSafariWebExtensionApplicationCanBePreflighted()
        async throws
    {
        guard
            let path = ProcessInfo.processInfo.environment[
                "CREST_TEST_SAFARI_EXTENSION_APP"
            ]
        else {
            throw XCTSkip(
                "Set CREST_TEST_SAFARI_EXTENSION_APP to a signed host app."
            )
        }

        let candidates = try await BrowserSafariWebExtensionInspector()
            .inspect(applicationURL: URL(fileURLWithPath: path))

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(
            candidates.allSatisfy {
                !$0.source.applicationBookmark.isEmpty
                    && !$0.source.extensionBundleIdentifier.isEmpty
            }
        )
    }

    private struct ExtensionFixture {
        let name: String
        let bundleIdentifier: String
        let extensionPointIdentifier: String
        let version: String
    }

    private func makeApplication(
        name: String,
        bundleIdentifier: String,
        extensions: [ExtensionFixture],
        directory: URL? = nil
    ) throws -> URL {
        let applicationURL = (directory ?? temporaryDirectoryURL)
            .appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL =
            applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
        let plugInsURL =
            contentsURL
            .appendingPathComponent("PlugIns", isDirectory: true)
        try FileManager.default.createDirectory(
            at: plugInsURL,
            withIntermediateDirectories: true
        )
        try writePropertyList(
            [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": name,
                "CFBundleDisplayName": name,
                "CFBundlePackageType": "APPL",
            ],
            to: contentsURL.appendingPathComponent("Info.plist")
        )

        for fixture in extensions {
            let bundleURL =
                plugInsURL
                .appendingPathComponent("\(fixture.name).appex", isDirectory: true)
            let bundleContentsURL =
                bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(
                at: bundleContentsURL,
                withIntermediateDirectories: true
            )
            try writePropertyList(
                [
                    "CFBundleIdentifier": fixture.bundleIdentifier,
                    "CFBundleName": fixture.name,
                    "CFBundleDisplayName": fixture.name,
                    "CFBundleShortVersionString": fixture.version,
                    "CFBundlePackageType": "XPC!",
                    "NSExtension": [
                        "NSExtensionPointIdentifier":
                            fixture.extensionPointIdentifier
                    ],
                ],
                to: bundleContentsURL.appendingPathComponent("Info.plist")
            )
        }
        return applicationURL
    }

    private func writePropertyList(
        _ propertyList: [String: Any],
        to url: URL
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}
