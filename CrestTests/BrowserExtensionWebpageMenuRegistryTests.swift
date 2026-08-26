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
