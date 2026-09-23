import AppKit
import Foundation

/// Crest-owned actions placed ahead of an engine's page menu. Engines keep
/// their own editing and extension rows; these actions use Crest's Space and
/// tab routing after the menu closes.
struct BrowserPageContextMenuAction {
    enum Kind {
        case search
        case peek
        case split
        case space(SpaceID)

        init?(identifier: String) {
            switch identifier {
            case "search": self = .search
            case "peek": self = .peek
            case "split": self = .split
            default:
                guard identifier.hasPrefix("space:"),
                    let id = UUID(uuidString: String(identifier.dropFirst("space:".count)))
                else { return nil }
                self = .space(SpaceID(rawValue: id))
            }
        }

        var identifier: String {
            switch self {
            case .search: "search"
            case .peek: "peek"
            case .split: "split"
            case .space(let id): "space:\(id.rawValue.uuidString)"
            }
        }
    }

    let kind: Kind
    let title: String
    let symbolName: String
    let linkURL: URL?
    let selectionText: String?

    var isSpaceDestination: Bool {
        if case .space = kind { return true }
        return false
    }

    var engineValues: [String: String] {
        [
            "id": kind.identifier, "title": title, "symbol": symbolName,
            "group": isSpaceDestination ? "spaces" : "primary",
            "groupTitle": String(localized: "Open Link in Another Space"),
        ]
    }
}

extension BrowserPage {
    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction] {
        guard let context = navigationContext else { return [] }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        var actions: [BrowserPageContextMenuAction] = []

        if let linkURL, BrowserCorePolicy.acceptsExternalURL(linkURL),
            linkDestinationHost.canOpenLink(from: source)
        {
            for space in linkDestinationHost.otherSpaces(from: source) {
                actions.append(
                    BrowserPageContextMenuAction(
                        kind: .space(space.id), title: space.name,
                        symbolName: "square.stack.3d.up", linkURL: linkURL, selectionText: nil))
            }
            actions.append(
                BrowserPageContextMenuAction(
                    kind: .peek, title: String(localized: "Open Link in Peek"),
                    symbolName: "rectangle.on.rectangle", linkURL: linkURL, selectionText: nil))
            if splitLinkHost.canOpenLink(context.tabID, context.assignment) {
                actions.append(
                    BrowserPageContextMenuAction(
                        kind: .split, title: String(localized: "Open Link in Split View"),
                        symbolName: "rectangle.split.2x1", linkURL: linkURL, selectionText: nil))
            }
        }
        if let selectionText,
            let search = linkDestinationHost.selectionSearch(for: selectionText, from: source)
        {
            actions.append(
                BrowserPageContextMenuAction(
                    kind: .search, title: String(localized: "Search with \(search.provider.title)"),
                    symbolName: "magnifyingglass", linkURL: nil, selectionText: selectionText))
        }
        return actions
    }

    @discardableResult
    func performContextMenuAction(
        identifier: String, linkURL: URL?, selectionText: String?
    ) -> Bool {
        guard let kind = BrowserPageContextMenuAction.Kind(identifier: identifier),
            contextMenuActions(linkURL: linkURL, selectionText: selectionText)
                .contains(where: { $0.kind.identifier == kind.identifier }),
            let context = navigationContext
        else { return false }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        switch kind {
        case .search:
            guard let selectionText,
                let search = linkDestinationHost.selectionSearch(for: selectionText, from: source)
            else { return false }
            return linkDestinationHost.openLink(
                search.url, from: source, in: context.assignment)
        case .peek:
            guard let linkURL else { return false }
            openPeek(
                BrowserPeekRequest(
                    url: linkURL, sourceTabID: context.tabID, sourceTitle: context.title,
                    spaceAssignment: context.assignment, trigger: .contextMenu))
            return true
        case .split:
            guard let linkURL else { return false }
            openLinkInSplitView(linkURL)
            return true
        case .space(let id):
            guard let linkURL,
                let space = linkDestinationHost.otherSpaces(from: source).first(where: { $0.id == id })
            else { return false }
            return linkDestinationHost.openLink(
                linkURL, from: source, in: BrowserSpaceRuntimeAssignment(space: space))
        }
    }
}
