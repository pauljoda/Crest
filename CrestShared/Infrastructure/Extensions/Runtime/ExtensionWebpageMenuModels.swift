import Foundation

enum BrowserExtensionWebpageMenuItemType: String, Equatable, Sendable {
    case normal
    case checkbox
    case radio
    case separator
}

enum BrowserExtensionWebpageMenuMediaType: String, Equatable, Sendable {
    case audio
    case image
    case video
}

struct BrowserExtensionWebpageMenuDefinition: Equatable, Sendable {
    let id: String
    let parentID: String?
    let type: BrowserExtensionWebpageMenuItemType
    let title: String
    let contexts: Set<String>
    let documentURLPatterns: [String]
    let targetURLPatterns: [String]
    let enabled: Bool
    let visible: Bool

    /// Authored patterns Crest cannot turn into a WebKit match pattern.
    ///
    /// The compatibility runtime forwards every pattern an extension authored
    /// rather than dropping the unsupported ones. Dropping them emptied the
    /// list whenever *all* of an item's patterns were unsupported, and an
    /// empty list means "the extension authored no restriction" — so an item
    /// scoped to one site silently became an item on every site. An item whose
    /// authored patterns are all unsupported now matches nothing, and this
    /// records which patterns were lost so the log can say why.
    let unsupportedURLPatterns: [String]

    init(
        id: String,
        parentID: String?,
        type: BrowserExtensionWebpageMenuItemType,
        title: String,
        contexts: Set<String>,
        documentURLPatterns: [String],
        targetURLPatterns: [String],
        enabled: Bool,
        visible: Bool,
        unsupportedURLPatterns: [String] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.type = type
        self.title = title
        self.contexts = contexts
        self.documentURLPatterns = documentURLPatterns
        self.targetURLPatterns = targetURLPatterns
        self.enabled = enabled
        self.visible = visible
        self.unsupportedURLPatterns = unsupportedURLPatterns
    }

    /// True when every authored pattern in a non-empty list is unsupported,
    /// which is the case where the item can never appear.
    var matchesNothing: Bool {
        let unsupported = Set(unsupportedURLPatterns)
        let documentIsUnmatchable =
            !documentURLPatterns.isEmpty
            && documentURLPatterns.allSatisfy(unsupported.contains)
        let targetIsUnmatchable =
            !targetURLPatterns.isEmpty
            && targetURLPatterns.allSatisfy(unsupported.contains)
        return documentIsUnmatchable || targetIsUnmatchable
    }

    /// A one-line explanation for the log, or `nil` when nothing was lost.
    var unsupportedURLPatternDiagnostic: String? {
        guard !unsupportedURLPatterns.isEmpty else { return nil }
        let patterns = unsupportedURLPatterns.joined(separator: ", ")
        let consequence =
            matchesNothing
            ? "the item cannot appear anywhere"
            : "the item still matches its remaining patterns"
        return
            "menu item \(id) declares URL pattern(s) WebKit cannot match "
            + "(\(patterns)); \(consequence)"
    }
}

struct BrowserExtensionWebpageMenuContext: Equatable, Sendable {
    let pageURL: URL
    let documentURL: URL
    let linkURL: URL?
    let sourceURL: URL?
    let mediaType: BrowserExtensionWebpageMenuMediaType?
    let selectionText: String?
    let isEditable: Bool
    let isMainFrame: Bool

    init(
        pageURL: URL,
        documentURL: URL,
        linkURL: URL?,
        sourceURL: URL?,
        mediaType: BrowserExtensionWebpageMenuMediaType? = nil,
        selectionText: String?,
        isEditable: Bool,
        isMainFrame: Bool
    ) {
        self.pageURL = pageURL
        self.documentURL = documentURL
        self.linkURL = linkURL
        self.sourceURL = sourceURL
        self.mediaType = mediaType
        self.selectionText = selectionText
        self.isEditable = isEditable
        self.isMainFrame = isMainFrame
    }

    var targetURL: URL? {
        linkURL ?? sourceURL
    }

    var declaredContexts: Set<String> {
        var result: Set<String> = []
        if linkURL != nil { result.insert("link") }
        if let mediaType { result.insert(mediaType.rawValue) }
        if selectionText?.isEmpty == false { result.insert("selection") }
        if isEditable { result.insert("editable") }
        if !isMainFrame { result.insert("frame") }
        if result.isEmpty { result.insert("page") }
        return result
    }
}
