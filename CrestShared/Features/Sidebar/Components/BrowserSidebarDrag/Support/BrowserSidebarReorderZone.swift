import CoreGraphics

/// A measured region that can accept a lifted sidebar item. Zones are ranked by
/// specificity so a folder header or space segment layered inside a section wins
/// over the section behind it.
struct BrowserSidebarReorderZone: Equatable, Sendable {
    enum Target: Hashable, Sendable {
        /// An ordered run of rows.
        case section(BrowserSidebarReorderSection)
        /// A collapsed folder row: dropping lands the item inside the folder.
        case folder(FolderID)
        case currentFolder(FolderID)
        case currentTab(TabID)
        /// A space picker segment: dropping moves the item to that space.
        case space(BrowserSpaceRuntimeAssignment)
        /// The window's web-content area for a Space: dropping a tab there adds
        /// it to the cards already on show.
        case splitContent(BrowserSpaceRuntimeAssignment)
    }

    let target: Target
    let frame: CGRect
    var minimumHeight: CGFloat = 0

    /// Higher wins when zones overlap.
    ///
    /// The content area sits at zero, below every sidebar zone. It is the
    /// largest zone in the window and the only one a floating sidebar can be
    /// drawn on top of, so it must never outrank a list the pointer is
    /// genuinely inside.
    var specificity: Int {
        switch target {
        case .space: 3
        case .folder, .currentFolder, .currentTab: 2
        case .section: 1
        case .splitContent: 0
        }
    }

    /// Whether this is the window's content area — the one zone a sidebar can be
    /// drawn on top of, and the only one whose frame says nothing about what the
    /// pointer is aiming at while it is.
    var isContentArea: Bool {
        switch target {
        case .splitContent: true
        case .section, .folder, .currentFolder, .currentTab, .space: false
        }
    }

    /// Breaks ties between zones of equal specificity: a run nested inside
    /// another wins even when the two measure the same rectangle. Only sections
    /// nest; every other target is a leaf.
    var nestingDepth: Int {
        switch target {
        case .section(let section): section.nestingDepth
        case .folder, .currentFolder, .currentTab, .space, .splitContent: 0
        }
    }
}
