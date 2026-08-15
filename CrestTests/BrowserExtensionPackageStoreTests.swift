import Foundation
import XCTest
@testable import Crest

final class BrowserExtensionPackageStoreTests: XCTestCase {
    func testRemovingAPackageWhoseResourceDisappearsIsIdempotent() throws {
        let fileManager = MissingPackageFileManager()
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: URL(filePath: "/tmp/crest-missing-package-store"),
            removesRootOnDeinit: false
        )

        XCTAssertNoThrow(
            try store.removePackage(
                packageName: "extension.zip",
                in: SpaceID()
            )
        )
    }

    func testStagingCopiesAnExtensionIntoAnOwnedSpaceDirectory() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(path: "crest-extension-store-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = testRoot
            .appending(path: "source", directoryHint: .isDirectory)
        let staging = testRoot
            .appending(path: "staging", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appending(path: "manifest.json"))
        let store = BrowserExtensionPackageStore(fileManager: fileManager, rootURL: staging)

        let package = try store.stage(source, in: SpaceID())

        XCTAssertTrue(package.extensionID.hasPrefix("local."))
        XCTAssertTrue(fileManager.fileExists(atPath: package.resourceURL.path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: package.resourceURL.appending(path: "manifest.json").path
            )
        )
        XCTAssertTrue(package.resourceURL.path.hasPrefix(staging.path))
    }

    func testRestagingTheSameFolderKeepsOneIdentityAndANewStoredCopy() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-identity-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let source = testRoot
            .appending(path: "source", directoryHint: .isDirectory)
        let staging = testRoot
            .appending(path: "staging", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: source.appending(path: "manifest.json"))
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: staging
        )
        let spaceID = SpaceID()

        let first = try store.stage(source, in: spaceID)
        let second = try store.stage(source, in: spaceID)

        XCTAssertEqual(first.extensionID, second.extensionID)
        XCTAssertNotEqual(first.packageName, second.packageName)
    }

    func testADifferentFolderStagesUnderADifferentIdentity() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-distinct-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let staging = testRoot
            .appending(path: "staging", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: testRoot) }
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: staging
        )
        var identifiers: Set<String> = []
        for name in ["alpha", "beta"] {
            let source = testRoot
                .appending(path: name, directoryHint: .isDirectory)
            try fileManager.createDirectory(
                at: source,
                withIntermediateDirectories: true
            )
            try Data("{}".utf8).write(
                to: source.appending(path: "manifest.json")
            )
            identifiers.insert(try store.stage(source, in: SpaceID()).extensionID)
        }

        XCTAssertEqual(identifiers.count, 2)
    }

    func testAManifestKeySurvivesTheFolderBeingMoved() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-key-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let staging = testRoot
            .appending(path: "staging", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: testRoot) }
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: staging
        )
        let manifest = Data(
            #"{"manifest_version":3,"name":"Keyed","version":"1.0","key":"AAAB"}"#
                .utf8
        )
        var identifiers: Set<String> = []
        for name in ["before-move", "after-move"] {
            let source = testRoot
                .appending(path: name, directoryHint: .isDirectory)
            try fileManager.createDirectory(
                at: source,
                withIntermediateDirectories: true
            )
            try manifest.write(to: source.appending(path: "manifest.json"))
            identifiers.insert(try store.stage(source, in: SpaceID()).extensionID)
        }

        XCTAssertEqual(identifiers.count, 1)
    }

    func testDiscardRemovesOnlyTheStagedPackage() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(path: "crest-extension-discard-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = testRoot
            .appending(path: "source", directoryHint: .isDirectory)
        let staging = testRoot
            .appending(path: "staging", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appending(path: "manifest.json"))
        let store = BrowserExtensionPackageStore(fileManager: fileManager, rootURL: staging)
        let package = try store.stage(source, in: SpaceID())

        store.discard(package)

        XCTAssertFalse(fileManager.fileExists(atPath: package.resourceURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: source.path))
    }

    func testPersistentStoreReconstructsAStagedPackageFromItsSafeName() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-reconstruction-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let source = testRoot
            .appending(path: "source", directoryHint: .isDirectory)
        let packageRoot = testRoot
            .appending(path: "packages", directoryHint: .isDirectory)
        let spaceID = SpaceID()
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(
            to: source.appending(path: "manifest.json")
        )
        let firstStore = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: packageRoot,
            removesRootOnDeinit: false
        )

        let package = try firstStore.stage(source, in: spaceID)
        let reconstructedStore = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: packageRoot,
            removesRootOnDeinit: false
        )
        let reconstructedURL = try reconstructedStore.resourceURL(
            packageName: package.packageName,
            in: spaceID
        )

        XCTAssertEqual(
            reconstructedURL.standardizedFileURL.path,
            package.resourceURL.standardizedFileURL.path
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: reconstructedURL
                    .appending(path: "manifest.json")
                    .path
            )
        )
        XCTAssertThrowsError(
            try reconstructedStore.resourceURL(
                packageName: "../outside",
                in: spaceID
            )
        )
    }

    func testRemovingOneSpacesPackagesPreservesAnotherSpacesDirectory() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-space-deletion-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let source = testRoot
            .appending(path: "source", directoryHint: .isDirectory)
        let packageRoot = testRoot
            .appending(path: "packages", directoryHint: .isDirectory)
        let deletedSpaceID = SpaceID()
        let retainedSpaceID = SpaceID()
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(
            to: source.appending(path: "manifest.json")
        )
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: packageRoot
        )
        let deleted = try store.stage(source, in: deletedSpaceID)
        let retained = try store.stage(source, in: retainedSpaceID)

        try store.removePackages(in: deletedSpaceID)

        XCTAssertFalse(fileManager.fileExists(atPath: deleted.resourceURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: retained.resourceURL.path))
    }

    func testStagingRejectsASymbolicLinkNestedInsideAnUnpackedExtension() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-symlink-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let source = testRoot
            .appending(path: "source", directoryHint: .isDirectory)
        let staging = testRoot
            .appending(path: "staging", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(
            to: source.appending(path: "manifest.json")
        )
        try fileManager.createSymbolicLink(
            at: source.appending(path: "outside-link"),
            withDestinationURL: testRoot
        )
        let store = BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL: staging
        )

        XCTAssertThrowsError(
            try store.stage(source, in: SpaceID())
        ) { error in
            XCTAssertEqual(
                error as? BrowserExtensionPackageStoreError,
                .symbolicLink
            )
        }
    }
}

private final class MissingPackageFileManager: FileManager, @unchecked Sendable {
    override func fileExists(atPath path: String) -> Bool {
        true
    }

    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileNoSuchFile)
    }
}
