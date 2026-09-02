import AppKit
import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebpageMenuPolicyTests: XCTestCase {
    /// A source URL alone no longer implies a media context: the hit-test
    /// result reports the media kind separately, so `mediaType` is what puts
    /// `image` (or `audio` / `video`) into the declared contexts. A page whose
    /// click carried only a source URL is still a plain `page` click.
    func testImageContextIncludesImageAndAllButNotPlainPage() throws {
        let context = makeContext(
            sourceURL: "https://cdn.example.com/photo.webp",
            mediaType: .image
        )
        let definitions = [
            makeDefinition(id: "page", contexts: ["page"]),
            makeDefinition(id: "image", contexts: ["image"]),
            makeDefinition(id: "all", contexts: ["all"]),
        ]

        XCTAssertEqual(
            BrowserExtensionWebpageMenuPolicy.matchingDefinitions(
                definitions,
                context: context
            ).map(\.id),
            ["image", "all"]
        )
    }

    func testDocumentAndTargetPatternsUseFrameAndTargetURLs() throws {
        let context = makeContext(
            documentURL: "https://frame.example/article",
            linkURL: "https://allowed.example/destination"
        )
        let definitions = [
            makeDefinition(
                id: "matching",
                contexts: ["link"],
                documentURLPatterns: ["https://frame.example/*"],
                targetURLPatterns: ["https://allowed.example/*"]
            ),
            makeDefinition(
                id: "wrong-document",
                contexts: ["link"],
                documentURLPatterns: ["https://other.example/*"]
            ),
            makeDefinition(
                id: "wrong-target",
                contexts: ["link"],
                targetURLPatterns: ["https://blocked.example/*"]
            ),
        ]

        XCTAssertEqual(
            BrowserExtensionWebpageMenuPolicy.matchingDefinitions(
                definitions,
                context: context
            ).map(\.id),
            ["matching"]
        )
    }

    func testSelectionEditableAndFrameContextsAreIndependent() {
        let context = makeContext(
            selectionText: "selected words",
            isEditable: true,
            isMainFrame: false
        )
        let definitions = [
            makeDefinition(id: "selection", contexts: ["selection"]),
            makeDefinition(id: "editable", contexts: ["editable"]),
            makeDefinition(id: "frame", contexts: ["frame"]),
            makeDefinition(id: "image", contexts: ["image"]),
        ]

        XCTAssertEqual(
            BrowserExtensionWebpageMenuPolicy.matchingDefinitions(
                definitions,
                context: context
            ).map(\.id),
            ["selection", "editable", "frame"]
        )
    }

    func testHiddenItemsAreOmittedAndDisabledItemsRemainVisible() {
        let definitions = [
            makeDefinition(id: "hidden", visible: false),
            makeDefinition(id: "disabled", enabled: false),
        ]

        XCTAssertEqual(
            BrowserExtensionWebpageMenuPolicy.matchingDefinitions(
                definitions,
                context: makeContext()
            ).map(\.id),
            ["disabled"]
        )
    }

    func testSelectionPlaceholderIsExpandedWithoutChangingStoredTitle() {
        let definition = makeDefinition(
            id: "selection",
            title: "Search for %s",
            contexts: ["selection"]
        )

        XCTAssertEqual(
            BrowserExtensionWebpageMenuPolicy.title(
                for: definition,
                context: makeContext(selectionText: "Crest browser")
            ),
            "Search for Crest browser"
        )
        XCTAssertEqual(definition.title, "Search for %s")
    }

    func testNativeTreeMappingPreservesSubmenusSeparatorsAndActions() throws {
        let actionTarget = WebpageMenuActionTarget()
        let parent = NSMenuItem(
            title: "Parent",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: "Parent")
        let child = NSMenuItem(
            title: "Child",
            action: #selector(WebpageMenuActionTarget.perform(_:)),
            keyEquivalent: "k"
        )
        child.target = actionTarget
        submenu.items = [child, .separator()]
        parent.submenu = submenu
        let definitions = [
            makeDefinition(id: "parent", title: "Parent"),
            makeDefinition(
                id: "child",
                parentID: "parent",
                title: "Child"
            ),
            makeDefinition(
                id: "separator",
                parentID: "parent",
                type: .separator,
                title: ""
            ),
        ]

        let mapped = try BrowserExtensionWebpageMenuPolicy.nativeItems(
            [parent],
            definitions: definitions
        )

        XCTAssertEqual(mapped.map(\.definition.id), ["parent"])
        XCTAssertEqual(
            mapped[0].children.map(\.definition.id),
            ["child", "separator"]
        )
        XCTAssertTrue(mapped[0].nativeItem === parent)
        XCTAssertTrue(mapped[0].children[0].nativeItem === child)
        XCTAssertTrue(mapped[0].children[1].nativeItem.isSeparatorItem)
        XCTAssertEqual(child.action, #selector(WebpageMenuActionTarget.perform(_:)))
        XCTAssertTrue(child.target === actionTarget)
    }

    func testNativeTreeMismatchFailsClosed() {
        let native = NSMenuItem(
            title: "Only Native Item",
            action: nil,
            keyEquivalent: ""
        )
        let definitions = [
            makeDefinition(id: "first"),
            makeDefinition(id: "second"),
        ]

        XCTAssertThrowsError(
            try BrowserExtensionWebpageMenuPolicy.nativeItems(
                [native],
                definitions: definitions
            )
        )
    }

    func testNativeExtensionGroupIsUnwrappedForDefinitionMapping() throws {
        let first = NSMenuItem(
            title: "First",
            action: nil,
            keyEquivalent: ""
        )
        let second = NSMenuItem(
            title: "Second",
            action: nil,
            keyEquivalent: ""
        )
        let group = NSMenuItem(
            title: "Fixture Extension",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: "Fixture Extension")
        submenu.items = [first, second]
        group.submenu = submenu

        let mapped = try BrowserExtensionWebpageMenuPolicy.nativeItems(
            [group],
            definitions: [
                makeDefinition(id: "first"),
                makeDefinition(id: "second"),
            ]
        )

        XCTAssertEqual(mapped.map(\.definition.id), ["first", "second"])
        XCTAssertTrue(mapped[0].nativeItem === first)
        XCTAssertTrue(mapped[1].nativeItem === second)
    }

    func testTabMenuKeepsOnlyVisibleMatchingTabDefinitions() throws {
        let nativeItems = [
            NSMenuItem(title: "Page", action: nil, keyEquivalent: ""),
            NSMenuItem(title: "Tab", action: nil, keyEquivalent: ""),
            NSMenuItem(title: "Hidden", action: nil, keyEquivalent: ""),
            NSMenuItem(title: "Wrong Site", action: nil, keyEquivalent: ""),
        ]
        let group = NSMenuItem(
            title: "Fixture Extension",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: "Fixture Extension")
        submenu.items = nativeItems
        group.submenu = submenu
        let definitions = [
            makeDefinition(id: "page", contexts: ["page"]),
            makeDefinition(id: "tab", contexts: ["tab"]),
            makeDefinition(
                id: "hidden",
                contexts: ["tab"],
                visible: false
            ),
            makeDefinition(
                id: "wrong-site",
                contexts: ["tab"],
                documentURLPatterns: ["https://other.example/*"]
            ),
        ]

        let result = try BrowserExtensionWebpageMenuPolicy.tabItems(
            [group],
            definitions: definitions,
            pageURL: URL(string: "https://top.example/page")
        )

        XCTAssertEqual(result.map(\.title), ["Tab"])
    }

    /// An authored pattern list restricts an item to what it names.
    ///
    /// The compatibility runtime used to drop patterns WebKit cannot parse.
    /// When every pattern was unsupported the list arrived empty, and an empty
    /// list means "no restriction authored" — so an item scoped to one
    /// extension's own pages appeared on every webpage instead. Unsupported
    /// patterns now arrive intact and match nothing.
    func testUnparseablePatternsMatchNothingRatherThanEverything() throws {
        let context = makeContext(
            documentURL: "https://top.example/page",
            linkURL: "https://target.example/file"
        )
        // Every item declares `all` so the context test cannot decide the
        // outcome: a click on a link is a `link` context and not a `page`
        // one, and this test is about the URL patterns, not the contexts.
        let definitions = [
            makeDefinition(
                id: "unsupported-document",
                contexts: ["all"],
                documentURLPatterns: ["not a match pattern"]
            ),
            makeDefinition(
                id: "unsupported-target",
                contexts: ["all"],
                targetURLPatterns: ["javascript:void(0)"]
            ),
            makeDefinition(
                id: "partially-supported",
                contexts: ["all"],
                documentURLPatterns: [
                    "not a match pattern",
                    "https://top.example/*",
                ]
            ),
            makeDefinition(id: "unrestricted", contexts: ["all"]),
        ]

        XCTAssertEqual(
            BrowserExtensionWebpageMenuPolicy.matchingDefinitions(
                definitions,
                context: context
            ).map(\.id),
            ["partially-supported", "unrestricted"]
        )
        XCTAssertEqual(
            try BrowserExtensionWebpageMenuPolicy.tabItems(
                definitions.map { definition in
                    let item = NSMenuItem()
                    item.title = definition.id
                    return item
                },
                definitions: definitions.map {
                    makeDefinition(
                        id: $0.id,
                        contexts: ["tab"],
                        documentURLPatterns: $0.documentURLPatterns,
                        targetURLPatterns: $0.targetURLPatterns
                    )
                },
                pageURL: URL(string: "https://top.example/page")
            ).map(\.title),
            ["partially-supported", "unrestricted"]
        )
    }

    /// The diagnostic exists so an item that can never appear says so.
    func testUnsupportedPatternDiagnosticNamesTheLostPatterns() {
        let unmatchable = BrowserExtensionWebpageMenuDefinition(
            id: "unmatchable",
            parentID: nil,
            type: .normal,
            title: "Unmatchable",
            contexts: ["page"],
            documentURLPatterns: ["not a match pattern"],
            targetURLPatterns: [],
            enabled: true,
            visible: true,
            unsupportedURLPatterns: ["not a match pattern"]
        )
        XCTAssertTrue(unmatchable.matchesNothing)
        let diagnostic = unmatchable.unsupportedURLPatternDiagnostic
        XCTAssertNotNil(diagnostic)
        XCTAssertTrue(
            diagnostic?.contains("not a match pattern") == true
        )
        XCTAssertTrue(
            diagnostic?.contains("cannot appear anywhere") == true
        )

        let partial = BrowserExtensionWebpageMenuDefinition(
            id: "partial",
            parentID: nil,
            type: .normal,
            title: "Partial",
            contexts: ["page"],
            documentURLPatterns: [
                "not a match pattern",
                "https://top.example/*",
            ],
            targetURLPatterns: [],
            enabled: true,
            visible: true,
            unsupportedURLPatterns: ["not a match pattern"]
        )
        XCTAssertFalse(partial.matchesNothing)
        XCTAssertTrue(
            partial.unsupportedURLPatternDiagnostic?
                .contains("remaining patterns") == true
        )

        XCTAssertNil(
            makeDefinition(id: "clean").unsupportedURLPatternDiagnostic
        )
    }

    private func makeContext(
        pageURL: String = "https://top.example/page",
        documentURL: String = "https://top.example/page",
        linkURL: String? = nil,
        sourceURL: String? = nil,
        mediaType: BrowserExtensionWebpageMenuMediaType? = nil,
        selectionText: String? = nil,
        isEditable: Bool = false,
        isMainFrame: Bool = true
    ) -> BrowserExtensionWebpageMenuContext {
        BrowserExtensionWebpageMenuContext(
            pageURL: URL(string: pageURL)!,
            documentURL: URL(string: documentURL)!,
            linkURL: linkURL.flatMap(URL.init(string:)),
            sourceURL: sourceURL.flatMap(URL.init(string:)),
            mediaType: mediaType,
            selectionText: selectionText,
            isEditable: isEditable,
            isMainFrame: isMainFrame
        )
    }

    private func makeDefinition(
        id: String,
        parentID: String? = nil,
        type: BrowserExtensionWebpageMenuItemType = .normal,
        title: String? = nil,
        contexts: Set<String> = ["page"],
        documentURLPatterns: [String] = [],
        targetURLPatterns: [String] = [],
        enabled: Bool = true,
        visible: Bool = true
    ) -> BrowserExtensionWebpageMenuDefinition {
        BrowserExtensionWebpageMenuDefinition(
            id: id,
            parentID: parentID,
            type: type,
            title: title ?? id,
            contexts: contexts,
            documentURLPatterns: documentURLPatterns,
            targetURLPatterns: targetURLPatterns,
            enabled: enabled,
            visible: visible
        )
    }
}

@MainActor
private final class WebpageMenuActionTarget: NSObject {
    @objc func perform(_: NSMenuItem) {}
}
