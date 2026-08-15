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
                atPath: packageRootURL
                    .appending(
                        path: space.id.rawValue.uuidString.lowercased(),
                        directoryHint: .isDirectory
                    )
                    .appending(path: firstPackageName).path
            )
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
