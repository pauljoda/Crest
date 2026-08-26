import Foundation

enum BrowserExtensionWebpageMenuItemType: String, Equatable, Sendable {
    case normal
    case checkbox
    case radio
    case separator
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
    let selectionText: String?
    let isEditable: Bool
    let isMainFrame: Bool

    var targetURL: URL? {
        linkURL ?? sourceURL
    }

    var declaredContexts: Set<String> {
        var result: Set<String> = []
        if linkURL != nil { result.insert("link") }
        if sourceURL != nil { result.insert("image") }
        if selectionText?.isEmpty == false { result.insert("selection") }
        if isEditable { result.insert("editable") }
        if !isMainFrame { result.insert("frame") }
        if result.isEmpty { result.insert("page") }
        return result
    }
}
