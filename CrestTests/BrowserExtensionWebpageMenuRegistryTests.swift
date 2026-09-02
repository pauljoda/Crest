import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebpageMenuRegistryTests: XCTestCase {
    func testDefinitionsAreIsolatedByVerifiedRuntimeClient() throws {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let work = try XCTUnwrap(BrowserExtensionServiceClientID("work.extension"))
        let privateClient = try XCTUnwrap(
            BrowserExtensionServiceClientID("private.extension")
        )

        try registry.replaceDefinitions(
            message: makeMessage(id: "work-image", contexts: ["image"]),
            for: work
        )
        try registry.replaceDefinitions(
            message: makeMessage(id: "private-page", contexts: ["page"]),
            for: privateClient
        )

        XCTAssertEqual(registry.definitions(for: work).map(\.id), ["work-image"])
        XCTAssertEqual(
            registry.definitions(for: privateClient).map(\.id),
            ["private-page"]
        )
    }

    func testReplacementRefreshesEveryMenuOpeningInsteadOfMergingStaleItems()
        throws
    {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )
        try registry.replaceDefinitions(
            message: makeMessage(id: "first", contexts: ["page"]),
            for: client
        )

        try registry.replaceDefinitions(
            message: makeMessage(id: "second", contexts: ["image"]),
            for: client
        )

        XCTAssertEqual(registry.definitions(for: client).map(\.id), ["second"])
    }

    func testMalformedReplacementFailsClosedAndClearsPriorDefinitions() throws {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )
        try registry.replaceDefinitions(
            message: makeMessage(id: "first", contexts: ["page"]),
            for: client
        )

        XCTAssertThrowsError(
            try registry.replaceDefinitions(
                message: ["api": "contextMenus.replace", "items": "bad"],
                for: client
            )
        )
        XCTAssertTrue(registry.definitions(for: client).isEmpty)
    }

    func testClickPublicationCarriesOnlyTheOwningItemAndFreshTarget() throws {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )
        var messages: [[String: Any]] = []
        let token = registry.observeClicks(for: client) { message in
            messages.append(message)
        }
        let firstContext = BrowserExtensionWebpageMenuContext(
            pageURL: URL(string: "https://example.com/first")!,
            documentURL: URL(string: "https://example.com/first")!,
            linkURL: nil,
            sourceURL: URL(string: "https://cdn.example.com/first.webp"),
            mediaType: .image,
            selectionText: nil,
            isEditable: false,
            isMainFrame: true
        )
        let secondContext = BrowserExtensionWebpageMenuContext(
            pageURL: URL(string: "https://example.com/second")!,
            documentURL: URL(string: "https://example.com/frame")!,
            linkURL: URL(string: "https://example.com/destination"),
            sourceURL: nil,
            selectionText: "fresh selection",
            isEditable: true,
            isMainFrame: false
        )

        registry.publishClick(
            menuItemID: "string:first",
            context: firstContext,
            for: client
        )
        registry.publishClick(
            menuItemID: "string:second",
            context: secondContext,
            for: client
        )
        registry.removeClickObserver(token, for: client)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["mediaType"] as? String, "image")
        XCTAssertEqual(messages[1]["menuItemID"] as? String, "string:second")
        XCTAssertEqual(
            messages[1]["pageURL"] as? String,
            "https://example.com/second"
        )
        XCTAssertEqual(
            messages[1]["documentURL"] as? String,
            "https://example.com/frame"
        )
        XCTAssertEqual(
            messages[1]["linkURL"] as? String,
            "https://example.com/destination"
        )
        XCTAssertEqual(messages[1]["selectionText"] as? String, "fresh selection")
        XCTAssertEqual(messages[1]["editable"] as? Bool, true)
        XCTAssertEqual(messages[1]["mainFrame"] as? Bool, false)
        XCTAssertNil(messages[1]["mediaType"])
    }

    func testClickPublishedWhileWorkerIsDisconnectedIsDeliveredOnceOnReconnect()
        throws
    {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )
        let context = BrowserExtensionWebpageMenuContext(
            pageURL: URL(string: "https://example.com/article")!,
            documentURL: URL(string: "https://example.com/article")!,
            linkURL: nil,
            sourceURL: URL(string: "https://cdn.example.com/photo.webp")!,
            mediaType: .image,
            selectionText: nil,
            isEditable: false,
            isMainFrame: true
        )
        registry.publishClick(
            menuItemID: "string:image",
            context: context,
            for: client
        )

        var firstConnectionMessages: [[String: Any]] = []
        let token = registry.observeClicks(for: client) {
            firstConnectionMessages.append($0)
        }
        registry.removeClickObserver(token, for: client)
        var secondConnectionMessages: [[String: Any]] = []
        _ = registry.observeClicks(for: client) {
            secondConnectionMessages.append($0)
        }

        XCTAssertEqual(firstConnectionMessages.count, 1)
        XCTAssertEqual(
            firstConnectionMessages.first?["menuItemID"] as? String,
            "string:image"
        )
        XCTAssertEqual(
            firstConnectionMessages.first?["mediaType"] as? String,
            "image"
        )
        XCTAssertTrue(secondConnectionMessages.isEmpty)
    }

    func testDownloadInvocationConsumesTheFreshOwningTabAndImageContextOnce()
        throws
    {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )
        let tabID = TabID()
        let context = BrowserExtensionWebpageMenuContext(
            pageURL: URL(string: "https://example.com/article")!,
            documentURL: URL(string: "https://frame.example/content")!,
            linkURL: nil,
            sourceURL: URL(string: "https://cdn.example/photo.webp")!,
            mediaType: .image,
            selectionText: nil,
            isEditable: false,
            isMainFrame: false
        )

        registry.publishClick(
            menuItemID: "string:save-jpeg",
            context: context,
            tabID: tabID,
            for: client
        )

        let invocation = try XCTUnwrap(
            registry.consumeDownloadInvocation(for: client)
        )
        XCTAssertEqual(invocation.tabID, tabID)
        XCTAssertEqual(invocation.menuItemID, "string:save-jpeg")
        XCTAssertEqual(invocation.context, context)
        XCTAssertNil(registry.consumeDownloadInvocation(for: client))
    }

    func testRemovingClientDropsDefinitionsAndClickObservers() throws {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )
        var clickCount = 0
        _ = registry.observeClicks(for: client) { _ in clickCount += 1 }
        try registry.replaceDefinitions(
            message: makeMessage(id: "page", contexts: ["page"]),
            for: client
        )

        registry.removeClient(client)
        registry.publishClick(
            menuItemID: "string:page",
            context: BrowserExtensionWebpageMenuContext(
                pageURL: URL(string: "https://example.com")!,
                documentURL: URL(string: "https://example.com")!,
                linkURL: nil,
                sourceURL: nil,
                selectionText: nil,
                isEditable: false,
                isMainFrame: true
            ),
            for: client
        )

        XCTAssertTrue(registry.definitions(for: client).isEmpty)
        XCTAssertEqual(clickCount, 0)
    }

    func testPendingInstallLifecycleIsIsolatedAndAcknowledgedExactlyOnce()
        throws
    {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let work = try XCTUnwrap(
            BrowserExtensionServiceClientID("shared.extension.work")
        )
        let privateClient = try XCTUnwrap(
            BrowserExtensionServiceClientID("shared.extension.private")
        )
        let eventID = registry.prepareInstallLifecycle(
            reason: .install,
            previousVersion: nil,
            for: work
        )

        let message = try XCTUnwrap(
            registry.pendingInstallLifecycleMessage(for: work)
        )
        XCTAssertEqual(message["api"] as? String, "runtime.onInstalled")
        XCTAssertEqual(message["eventID"] as? String, eventID)
        XCTAssertEqual(message["reason"] as? String, "install")
        XCTAssertNil(message["previousVersion"])
        XCTAssertNil(
            registry.pendingInstallLifecycleMessage(for: privateClient)
        )

        XCTAssertFalse(
            registry.acknowledgeInstallLifecycle(
                eventID: "wrong-event",
                for: work
            )
        )
        XCTAssertNotNil(registry.pendingInstallLifecycleMessage(for: work))
        XCTAssertTrue(
            registry.acknowledgeInstallLifecycle(
                eventID: eventID,
                for: work
            )
        )
        XCTAssertNil(registry.pendingInstallLifecycleMessage(for: work))
        XCTAssertFalse(
            registry.acknowledgeInstallLifecycle(
                eventID: eventID,
                for: work
            )
        )
    }

    /// An unsupported pattern must not cost an extension its whole menu
    /// transaction, and must not silently widen the item it scopes.
    ///
    /// The registry keeps every authored pattern, records the ones WebKit
    /// cannot parse, and restores them verbatim — a filtered list would arrive
    /// empty, and an empty list means "unrestricted".
    func testUnparseablePatternsAreRecordedRatherThanDroppedOrRejected()
        throws
    {
        let registry = BrowserExtensionWebpageMenuRegistry()
        let client = try XCTUnwrap(
            BrowserExtensionServiceClientID("work.extension")
        )

        try registry.replaceDefinitions(
            message: [
                "api": "contextMenus.replace",
                "items": [
                    [
                        "id": "scoped",
                        "type": "normal",
                        "title": "Scoped",
                        "contexts": ["page"],
                        "documentUrlPatterns": [
                            "not a match pattern",
                            "https://example.com/*",
                        ],
                        "targetUrlPatterns": [],
                        "enabled": true,
                        "visible": true,
                    ] as [String: Any]
                ],
            ],
            for: client
        )

        let definition = try XCTUnwrap(
            registry.definitions(for: client).first
        )
        XCTAssertEqual(
            definition.documentURLPatterns,
            ["not a match pattern", "https://example.com/*"]
        )
        XCTAssertEqual(
            definition.unsupportedURLPatterns,
            ["not a match pattern"]
        )
        XCTAssertFalse(definition.matchesNothing)
        XCTAssertNotNil(definition.unsupportedURLPatternDiagnostic)

        let restoration = try XCTUnwrap(
            registry.restorationMessage(for: client)
        )
        let items = try XCTUnwrap(restoration["items"] as? [[String: Any]])
        XCTAssertEqual(
            items.first?["documentUrlPatterns"] as? [String],
            ["not a match pattern", "https://example.com/*"]
        )
    }

    private func makeMessage(
        id: String,
        contexts: [String]
    ) -> [String: Any] {
        [
            "api": "contextMenus.replace",
            "items": [
                [
                    "id": id,
                    "type": "normal",
                    "title": id,
                    "contexts": contexts,
                    "documentUrlPatterns": [],
                    "targetUrlPatterns": [],
                    "enabled": true,
                    "visible": true,
                ] as [String: Any]
            ],
        ]
    }
}

final class BrowserExtensionDownloadRequestTests: XCTestCase {
    func testAcceptsConvertedDataURLFilenameAndDestinationChoice() throws {
        let request = try BrowserExtensionDownloadRequest(
            message: [
                "api": "downloads.download",
                "url": "data:image/jpeg;base64,/9j/2Q==",
                "filename": "converted/photo.jpg",
                "saveAs": true,
            ],
            extensionBaseURL: URL(
                string: "crest-extension://download-fixture/"
            )!
        )

        XCTAssertEqual(request.url.scheme, "data")
        XCTAssertEqual(request.filename, "converted/photo.jpg")
        XCTAssertTrue(request.saveAs)
    }

    func testRejectsHostFilesystemAndScriptURLs() {
        for rawURL in [
            "file:///Users/example/secret.jpg",
            "javascript:alert(1)",
            "blob:https://example.com/not-transferable",
        ] {
            XCTAssertThrowsError(
                try BrowserExtensionDownloadRequest(
                    message: [
                        "api": "downloads.download",
                        "url": rawURL,
                    ],
                    extensionBaseURL: URL(
                        string: "crest-extension://download-fixture/"
                    )!
                ),
                "Unexpectedly accepted \(rawURL)"
            )
        }
    }

    func testAcceptsOwningExtensionResourcesButNotAnotherExtension() throws {
        let baseURL = URL(
            string: "crest-extension://download-fixture/"
        )!

        XCTAssertNoThrow(
            try BrowserExtensionDownloadRequest(
                message: [
                    "api": "downloads.download",
                    "url": "crest-extension://download-fixture/export.jpg",
                ],
                extensionBaseURL: baseURL
            )
        )
        XCTAssertThrowsError(
            try BrowserExtensionDownloadRequest(
                message: [
                    "api": "downloads.download",
                    "url": "crest-extension://other-extension/export.jpg",
                ],
                extensionBaseURL: baseURL
            )
        )
    }
}

final class BrowserExtensionOffscreenDocumentRequestTests: XCTestCase {
    private let extensionBaseURL = URL(
        string: "crest-extension://offscreen-owner/"
    )!

    func testAcceptsRelativeAndOwningExtensionDocumentURLs() throws {
        let relative = try BrowserExtensionOffscreenDocumentRequest(
            message: [
                "api": "offscreen.createDocument",
                "url": "offscreen.html",
                "reasons": ["DOM_SCRAPING"],
                "justification": "Convert an image",
            ],
            extensionBaseURL: extensionBaseURL
        )
        XCTAssertEqual(
            relative.url,
            extensionBaseURL.appending(path: "offscreen.html")
        )
        XCTAssertEqual(relative.reasons, ["DOM_SCRAPING"])
        XCTAssertEqual(relative.justification, "Convert an image")

        let absolute = try BrowserExtensionOffscreenDocumentRequest(
            message: [
                "api": "offscreen.createDocument",
                "url": extensionBaseURL.appending(path: "worker.html")
                    .absoluteString,
                "reasons": ["WORKERS"],
                "justification": "Run a worker",
            ],
            extensionBaseURL: extensionBaseURL
        )
        XCTAssertEqual(
            absolute.url,
            extensionBaseURL.appending(path: "worker.html")
        )
    }

    func testRejectsForeignAndNonExtensionDocumentURLs() {
        for url in [
            "https://example.com/offscreen.html",
            "crest-extension://another-extension/offscreen.html",
        ] {
            XCTAssertThrowsError(
                try BrowserExtensionOffscreenDocumentRequest(
                    message: [
                        "api": "offscreen.createDocument",
                        "url": url,
                        "reasons": ["DOM_SCRAPING"],
                        "justification": "Convert an image",
                    ],
                    extensionBaseURL: extensionBaseURL
                )
            )
        }
    }

    func testRejectsMissingCreationPurpose() {
        XCTAssertThrowsError(
            try BrowserExtensionOffscreenDocumentRequest(
                message: [
                    "api": "offscreen.createDocument",
                    "url": "offscreen.html",
                    "reasons": [],
                    "justification": "",
                ],
                extensionBaseURL: extensionBaseURL
            )
        )
    }
}
