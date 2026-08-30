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
