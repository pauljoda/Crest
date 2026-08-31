import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit
import XCTest

@testable import Crest

final class BrowserDownloadTransferTests: XCTestCase {
    func testStagingURLLivesInsideTheAppOwnedDirectory() {
        let directory = URL(fileURLWithPath: "/Application Support/Crest/Download Staging", isDirectory: true)
        let itemID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let url = BrowserDownloadTransfer.stagingURL(
            itemID: itemID,
            suggestedFilename: "report.pdf",
            directory: directory
        )

        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(url.lastPathComponent.contains(itemID.uuidString))
    }

    func testFinishingMovesTheStagedFileToItsVisibleDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(from: staging, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
    }

    func testFinishingAWebDownloadAppliesSystemQuarantineMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
        let sourceURL = try XCTUnwrap(URL(string: "https://downloads.example/report.txt"))
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(
            from: staging,
            to: destination,
            quarantine: BrowserDownloadQuarantine(
                sourceURL: sourceURL,
                timestamp: Date(timeIntervalSince1970: 1_000),
                agentName: "Crest Tests",
                agentBundleIdentifier: "com.pauldavis.crest.tests"
            )
        )

        let properties = try destination.resourceValues(forKeys: [.quarantinePropertiesKey])
            .quarantineProperties
        XCTAssertNotNil(properties)
        XCTAssertFalse((properties?["LSQuarantineAgentName"] as? String)?.isEmpty ?? true)
    }

    @MainActor
    func testExtensionJPEGUsesRequestedFilenameAndStandardCompletionLifecycle()
        async throws
    {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-extension-download-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: downloads,
            withIntermediateDirectories: true
        )
        try Data("occupied".utf8).write(
            to: downloads.appending(path: "converted.jpg")
        )
        var forcedDestinationPrompt = false
        let center = BrowserDownloadCenter(
            resolveDownloadDestination: { suggestedFilename, _, forcesPrompt in
                forcedDestinationPrompt = forcesPrompt
                return .destination(
                    BrowserDownloadDestination.availableURL(
                        suggestedFilename: suggestedFilename,
                        directory: downloads,
                        fileExists: {
                            FileManager.default.fileExists(atPath: $0.path)
                        }
                    ),
                    securityScopedURL: nil
                )
            }
        )
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 2,
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.setColor(.systemBlue, atX: 0, y: 0)
        let jpeg = try XCTUnwrap(
            bitmap.representation(using: .jpeg, properties: [:])
        )
        let request = try BrowserExtensionDownloadRequest(
            message: [
                "api": "downloads.download",
                "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
                "filename": "converted.jpg",
                "saveAs": true,
            ],
            extensionBaseURL: URL(string: "crest-extension://fixture/")!
        )
        let profileID = UUID()

        let downloadID = await center.startExtensionDownload(
            request,
            in: WKWebView(),
            profileID: profileID,
            spaceID: SpaceID(rawValue: UUID()),
            spaceName: "Fixture",
            isUserInitiated: true
        )
        for _ in 0..<200 {
            guard center.items.first?.state != .finished else { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        let item = try XCTUnwrap(center.items.first)
        let destination = try XCTUnwrap(item.destinationURL)
        XCTAssertEqual(downloadID, 1)
        XCTAssertTrue(forcedDestinationPrompt)
        XCTAssertEqual(item.profileID, profileID)
        XCTAssertEqual(item.filename, "converted 1.jpg")
        XCTAssertEqual(item.state, .finished)
        XCTAssertEqual(destination.lastPathComponent, "converted 1.jpg")
        let savedData = try Data(contentsOf: destination)
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(savedData as CFData, nil)
        )
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    }
}
