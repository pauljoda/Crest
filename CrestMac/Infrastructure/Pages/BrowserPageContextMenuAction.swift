import AppKit
import Foundation

/// Crest-owned actions placed ahead of an engine's page menu. Engines keep
/// their own editing and extension rows; these actions use Crest's Space and
/// tab routing after the menu closes. Each row carries what it does to the
/// page, given the page's navigation context and the tab it comes from.
struct BrowserPageContextMenuAction {
    // MARK: - Types

    /// Which row this is, with what it does it to.
    enum Kind: Equatable {
        case newTab
        case search
        case peek
        case split
        case space(UUID)
    }

    /// Runs the row on the page, answering whether it did.
    typealias Perform =
        @MainActor (BrowserPage, BrowserPageNavigationContext, BrowserTabRuntimeAssignment) -> Bool

    // MARK: - Variables

    let kind: Kind
    /// The row of the link menu preferences this row is, which says whether
    /// and where the menu shows it.
    let row: LinkMenuRow
    let title: String
    let symbolName: String
    let linkURL: URL?
    let selectionText: String?
    /// The Space a Space destination opens the link in, whose icon its row
    /// shows; nil for every other row.
    var space: BrowserSpaceIdentity?
    let perform: Perform

    var isSpaceDestination: Bool {
        if case .space = kind { return true }
        return false
    }

    /// Whether this row opens the link in a new tab of the page's Space, as
    /// an engine's own new-tab item does.
    var opensNewTab: Bool { row == .newTab }

    // MARK: - Initializers

    init(
        kind: Kind, row: LinkMenuRow, title: String, symbolName: String, linkURL: URL?, selectionText: String?,
        space: BrowserSpaceIdentity? = nil, perform: @escaping Perform
    ) {
        self.kind = kind
        self.row = row
        self.title = title
        self.symbolName = symbolName
        self.linkURL = linkURL
        self.selectionText = selectionText
        self.space = space
        self.perform = perform
    }

    // MARK: - Actions - Rows

    /// Opens `linkURL` in a new tab of the page's Space.
    static func newTab(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .newTab, row: .newTab, title: String(localized: "Open Link in New Tab"),
            symbolName: "plus.square.on.square", linkURL: linkURL, selectionText: nil
        ) { page, context, source in
            page.linkDestinationHost.openLink(linkURL, from: source, in: context.assignment)
        }
    }

    /// Opens `linkURL` in `space`, another Space of the window.
    @MainActor static func space(_ space: SpaceModel, opening linkURL: URL) -> BrowserPageContextMenuAction {
        let id = space.id
        return BrowserPageContextMenuAction(
            kind: .space(id), row: .otherSpaces, title: space.settings.name, symbolName: "square.stack.3d.up",
            linkURL: linkURL, selectionText: nil, space: space.identity
        ) { page, _, source in
            guard let space = page.linkDestinationHost.otherSpaces(from: source).first(where: { $0.id == id })
            else { return false }
            return page.linkDestinationHost.openLink(
                linkURL, from: source, in: BrowserSpaceRuntimeAssignment(space: space))
        }
    }

    /// Opens `linkURL` in Peek over the page.
    static func peek(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .peek, row: .peek, title: String(localized: "Open Link in Peek"),
            symbolName: "rectangle.on.rectangle", linkURL: linkURL, selectionText: nil
        ) { page, context, _ in
            page.openPeek(
                BrowserPeekRequest(
                    url: linkURL, sourceTabID: context.tabID, sourceTitle: context.title,
                    spaceAssignment: context.assignment, trigger: .contextMenu))
            return true
        }
    }

    /// Opens `linkURL` in a split view beside the page's tab.
    static func split(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .split, row: .splitView, title: String(localized: "Open Link in Split View"),
            symbolName: "rectangle.split.2x1", linkURL: linkURL, selectionText: nil
        ) { page, _, _ in
            page.openLinkInSplitView(linkURL)
            return true
        }
    }

    /// Searches for `selectionText` with the engine titled `engineTitle`.
    static func search(_ selectionText: String, with engineTitle: String) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .search, row: .search, title: String(localized: "Search with \(engineTitle)"),
            symbolName: "magnifyingglass", linkURL: nil, selectionText: selectionText
        ) { page, context, source in
            guard let search = page.linkDestinationHost.selectionSearch(for: selectionText, from: source)
            else { return false }
            return page.linkDestinationHost.openLink(search.url, from: source, in: context.assignment)
        }
    }
}

/// A page that puts Crest's rows in an engine's context menu and runs the one
/// the person picks.
@MainActor
protocol BrowserPageContextMenuHost: AnyObject {
    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction]
    @discardableResult func performContextMenuAction(_ action: BrowserPageContextMenuAction) -> Bool
}

/// Crest's rows in an engine's context menu for one page, ahead of the
/// engine's rows, in the order the link menu preferences set, with the other
/// Spaces a link opens in grouped under one row. A row runs only while the
/// page's view is still in the window the menu opened in.
@MainActor
struct BrowserPageContextMenu {
    // MARK: - Types

    /// One row's action, which its menu item keeps and runs.
    @MainActor
    private final class Row: NSObject {
        let action: BrowserPageContextMenuAction
        weak var host: (any BrowserPageContextMenuHost)?
        weak var view: NSView?
        let windowNumber: Int?

        init(_ action: BrowserPageContextMenuAction, host: any BrowserPageContextMenuHost, view: NSView) {
            self.action = action
            self.host = host
            self.view = view
            windowNumber = view.window?.windowNumber
        }

        /// Runs the row on the main queue's next turn, once the engine's menu
        /// and the engine code that showed it have returned, while the page's
        /// view is still in the window the menu opened in.
        ///
        /// The Objective-C name is spelled out: a method named `perform(_:)`
        /// makes `#selector` pick NSObject's `performSelector:`, which sends
        /// the menu item itself as a selector and raises.
        @objc(runContextMenuRow:) func run(_ sender: NSMenuItem) {
            Task { @MainActor in
                guard let view, view.window?.windowNumber == windowNumber else { return }
                host?.performContextMenuAction(action)
            }
        }
    }

    // MARK: - Variables

    /// The rows the menu shows, in the order the link menu preferences set.
    let actions: [BrowserPageContextMenuAction]
    let host: any BrowserPageContextMenuHost
    /// The page's view, whose window the menu opened in.
    let view: NSView

    // MARK: - Initializers

    /// A menu of the `actions` a page offers, leaving out and ordering rows
    /// as the link menu preferences say.
    init(actions: [BrowserPageContextMenuAction], host: any BrowserPageContextMenuHost, view: NSView) {
        self.actions = BrowserAppPreferenceStore.shared.linkMenu.arranging(actions)
        self.host = host
        self.view = view
    }

    // MARK: - Actions - Menu

    /// Puts the rows ahead of what `menu` holds, with a separator between,
    /// the other Spaces grouped under one row where the first of them stands.
    /// The engine's own `newTab` item, which opens the link in a new tab,
    /// takes the place of Crest's new-tab row and keeps its action.
    func insert(into menu: NSMenu, newTab engineNewTab: NSMenuItem? = nil) {
        defer { removeStraySeparators(from: menu) }
        guard !actions.isEmpty else { return }
        var items: [NSMenuItem] = []
        var spaces: NSMenu?
        for action in actions {
            if action.isSpaceDestination {
                if spaces == nil {
                    let group = NSMenuItem(
                        title: String(localized: "Open Link in Another Space"), action: nil, keyEquivalent: "")
                    group.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
                    group.submenu = NSMenu()
                    spaces = group.submenu
                    items.append(group)
                }
                spaces?.addItem(item(for: action))
            } else if action.opensNewTab, let engineNewTab, menu.items.contains(engineNewTab) {
                menu.removeItem(engineNewTab)
                items.append(engineNewTab)
            } else {
                items.append(item(for: action))
            }
        }
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        if menu.items.count > items.count { menu.insertItem(.separator(), at: items.count) }
    }

    /// Drops separators left at either end of `menu` or next to another once
    /// an item moved or was hidden out from between them.
    private func removeStraySeparators(from menu: NSMenu) {
        for index in menu.items.indices.reversed() where menu.items[index].isSeparatorItem {
            let atEdge = index == 0 || index == menu.items.count - 1
            let doubled = index + 1 < menu.items.count && menu.items[index + 1].isSeparatorItem
            if atEdge || doubled { menu.removeItem(at: index) }
        }
    }

    private func item(for action: BrowserPageContextMenuAction) -> NSMenuItem {
        let row = Row(action, host: host, view: view)
        let item = NSMenuItem(title: action.title, action: #selector(Row.run(_:)), keyEquivalent: "")
        item.target = row
        // The menu item keeps its row alive.
        item.representedObject = row
        item.image =
            action.space.flatMap { BrowserSpaceSymbolArtworkRenderer.shared.menuImage(for: $0) }
            ?? NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
        return item
    }
}

extension BrowserPage: BrowserPageContextMenuHost {
    /// The rows the page offers for `linkURL` and `selectionText`: a link's
    /// new tab, Peek, Split View and other Spaces where the page may open it,
    /// then a search for the selection.
    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction] {
        guard let context = navigationContext else { return [] }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        var actions: [BrowserPageContextMenuAction] = []

        if let linkURL, ExternalWebLink.accepts(linkURL),
            linkDestinationHost.canOpenLink(from: source)
        {
            actions.append(.newTab(linkURL))
            actions.append(.peek(linkURL))
            if splitLinkHost.canOpenLink(context.tabID, context.assignment) {
                actions.append(.split(linkURL))
            }
            for space in linkDestinationHost.otherSpaces(from: source) {
                actions.append(.space(space, opening: linkURL))
            }
        }
        if let selectionText,
            let search = linkDestinationHost.selectionSearch(for: selectionText, from: source)
        {
            actions.append(.search(selectionText, with: search.engineTitle))
        }
        return actions
    }

    /// Runs a row the menu offered, while the page still offers it for the
    /// same link or selection.
    @discardableResult
    func performContextMenuAction(_ action: BrowserPageContextMenuAction) -> Bool {
        guard
            contextMenuActions(linkURL: action.linkURL, selectionText: action.selectionText)
                .contains(where: { $0.kind == action.kind }),
            let context = navigationContext
        else { return false }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        return action.perform(self, context, source)
    }
}
