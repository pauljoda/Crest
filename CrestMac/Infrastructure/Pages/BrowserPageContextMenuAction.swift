import AppKit
import Foundation

/// Crest-owned actions placed around an engine's page menu: link and
/// selection rows ahead of it, page rows after it. Engines keep their own
/// editing and extension rows; these actions use Crest's Space and tab
/// routing after the menu closes. Each row carries what it does to the page,
/// given the page's navigation context and the tab it comes from.
struct BrowserPageContextMenuAction {
    // MARK: - Types

    /// Which row this is, with what it does it to.
    enum Kind: Equatable {
        case search
        case peek
        case split
        case space(UUID)
        case quickWindow
        case blockElement
    }

    /// Where a row sits around the engine's rows: ahead of them, in the group
    /// of Space destinations that stands where the first of them does, or
    /// after them, acting on the page rather than on a link or selection.
    enum Placement: Equatable {
        case leading
        case spaces
        case trailing
    }

    /// Runs the row on the page, answering whether it did. A page without a
    /// tab, as a Quick Window or Peek shows, has no navigation context.
    typealias Perform =
        @MainActor (BrowserPage, BrowserPageNavigationContext?, BrowserTabRuntimeAssignment?) -> Bool

    // MARK: - Variables

    let kind: Kind
    let placement: Placement
    let title: String
    let symbolName: String
    let linkURL: URL?
    let selectionText: String?
    /// The Space a Space destination opens the link in, whose icon its row
    /// shows; nil for every other row.
    var space: BrowserSpaceIdentity?
    let perform: Perform

    // MARK: - Initializers

    init(
        kind: Kind, placement: Placement = .leading, title: String, symbolName: String, linkURL: URL?,
        selectionText: String?, space: BrowserSpaceIdentity? = nil, perform: @escaping Perform
    ) {
        self.kind = kind
        self.placement = placement
        self.title = title
        self.symbolName = symbolName
        self.linkURL = linkURL
        self.selectionText = selectionText
        self.space = space
        self.perform = perform
    }

    // MARK: - Actions - Rows

    /// Opens `linkURL` in a Quick Window in the session of `space`, another
    /// Space of the window. Keep moves it into that Space as a tab.
    @MainActor static func space(_ space: SpaceModel, opening linkURL: URL) -> BrowserPageContextMenuAction {
        let id = space.id
        return BrowserPageContextMenuAction(
            kind: .space(id), placement: .spaces, title: space.settings.name, symbolName: "square.stack.3d.up",
            linkURL: linkURL,
            selectionText: nil, space: space.identity
        ) { page, _, source in
            guard let source,
                let space = page.linkDestinationHost.otherSpaces(from: source).first(where: { $0.id == id })
            else { return false }
            return page.openInQuickWindow(linkURL, in: space)
        }
    }

    /// Opens `linkURL` in a Quick Window of its own, in the page's Space, from
    /// a page without a tab, whose new-tab rows have no tab to open after.
    static func quickWindow(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .quickWindow, title: String(localized: "Open Link in New Quick Window"),
            symbolName: "macwindow.badge.plus", linkURL: linkURL, selectionText: nil
        ) { page, _, _ in
            page.openInQuickWindow(linkURL)
        }
    }

    /// Opens `linkURL` in Peek over the page.
    static func peek(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .peek, title: String(localized: "Open Link in Peek"), symbolName: "rectangle.on.rectangle",
            linkURL: linkURL, selectionText: nil
        ) { page, context, _ in
            guard let context else { return false }
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
            kind: .split, title: String(localized: "Open Link in Split View"), symbolName: "rectangle.split.2x1",
            linkURL: linkURL, selectionText: nil
        ) { page, _, _ in
            page.openLinkInSplitView(linkURL)
            return true
        }
    }

    /// Starts the element picker on what the person right-clicked, to block
    /// it on the page's site from now on.
    static let blockElement = BrowserPageContextMenuAction(
        kind: .blockElement, placement: .trailing, title: String(localized: "Block Element"), symbolName: "eye.slash",
        linkURL: nil,
        selectionText: nil
    ) { page, _, _ in
        Task { await page.pickElementToBlock(fromContextMenu: true) }
        return true
    }

    /// Searches for `selectionText` with the engine titled `engineTitle`.
    static func search(_ selectionText: String, with engineTitle: String) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .search, title: String(localized: "Search with \(engineTitle)"), symbolName: "magnifyingglass",
            linkURL: nil, selectionText: selectionText
        ) { page, context, source in
            guard let context, let source,
                let search = page.linkDestinationHost.selectionSearch(for: selectionText, from: source)
            else { return false }
            return page.linkDestinationHost.openLink(search.url, from: source, in: context.assignment)
        }
    }
}

/// Crest's rows in an engine's context menu for one page, ahead of the
/// engine's rows: the engine's own row that opens a link in a new tab, then
/// the page's rows in their order, the other Spaces the link opens in grouped
/// under one row where the first of them stands, with a separator between
/// their groups. A row runs only while the page's view is still in the window
/// the menu opened in.
@MainActor
struct BrowserPageContextMenu {
    // MARK: - Types

    /// One row's action, which its menu item keeps and runs.
    @MainActor
    private final class Row: NSObject {
        let action: BrowserPageContextMenuAction
        weak var host: BrowserPage?
        weak var view: NSView?
        let windowNumber: Int?

        init(_ action: BrowserPageContextMenuAction, host: BrowserPage, view: NSView) {
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

    let actions: [BrowserPageContextMenuAction]
    let host: BrowserPage
    /// The page's view, whose window the menu opened in.
    let view: NSView

    // MARK: - Actions - Menu

    /// Puts the rows ahead of what `menu` holds, with a separator between,
    /// after `newTab`, the engine's own row that opens the link in a new tab
    /// of the page's Space, which leads the menu wherever the engine put it.
    func insert(into menu: NSMenu, leading newTab: NSMenuItem? = nil) {
        var items: [NSMenuItem] = []
        if let newTab, host.opensLinksInCurrentSpace, menu.index(of: newTab) >= 0 {
            menu.removeItem(newTab)
            // An engine's row may come without an icon of its own.
            if newTab.image == nil {
                newTab.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
            }
            items.append(newTab)
        }
        var spaces: NSMenu?
        var previousSpace: BrowserPageContextMenuAction?
        for action in actions where action.placement != .trailing {
            guard action.placement == .spaces else {
                items.append(item(for: action))
                continue
            }
            if spaces == nil {
                let group = NSMenuItem(title: String(localized: "Open Link in"), action: nil, keyEquivalent: "")
                group.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
                group.submenu = NSMenu()
                spaces = group.submenu
                items.append(group)
            }
            // The Spaces of one group browse with one profile; a separator
            // stands where the next group begins.
            if let previousSpace, action.space?.profileID != previousSpace.space?.profileID {
                spaces?.addItem(.separator())
            }
            spaces?.addItem(item(for: action))
            previousSpace = action
        }
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        if !items.isEmpty, menu.items.count > items.count { menu.insertItem(.separator(), at: items.count) }
        let trailing = actions.filter { $0.placement == .trailing }.map(item(for:))
        if !trailing.isEmpty, menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
        for item in trailing { menu.addItem(item) }
        removeStraySeparators(from: menu)
    }

    /// Drops the separators that no longer stand between two groups, as one
    /// left where a row moved out of a group of its own.
    private func removeStraySeparators(from menu: NSMenu) {
        var previousIsSeparator = true
        for item in menu.items {
            if item.isSeparatorItem, previousIsSeparator {
                menu.removeItem(item)
                continue
            }
            previousIsSeparator = item.isSeparatorItem
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
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

/// A page puts Crest's rows in an engine's context menu and runs the one the
/// person picks.
extension BrowserPage {
    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction] {
        guard let context = linkNavigationContext else {
            guard let linkURL, ExternalWebLink.accepts(linkURL) else { return [] }
            return [.quickWindow(linkURL)]
        }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        var actions: [BrowserPageContextMenuAction] = []

        if let linkURL, ExternalWebLink.accepts(linkURL),
            linkDestinationHost.canOpenLink(from: source)
        {
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
        if canPickElementToBlock { actions.append(.blockElement) }
        return actions
    }

    /// Whether the page's bridge can start the element picker: Crest blocks,
    /// its engine blocks content and it shows a site on the web.
    private var canPickElementToBlock: Bool {
        cosmeticFilters?.blocksContent == true && pageEngine.registration.supports(.contentBlocking)
            && live.displayURL?.webScheme != nil
    }

    /// Runs a row the menu offered, while the page still offers it for the
    /// same link or selection.
    @discardableResult
    func performContextMenuAction(_ action: BrowserPageContextMenuAction) -> Bool {
        guard
            contextMenuActions(linkURL: action.linkURL, selectionText: action.selectionText)
                .contains(where: { $0.kind == action.kind })
        else { return false }
        let context = linkNavigationContext
        let source = context.map {
            BrowserTabRuntimeAssignment(tabID: $0.tabID, spaceID: $0.spaceID, profileID: $0.assignment.profileID)
        }
        return action.perform(self, context, source)
    }
}
