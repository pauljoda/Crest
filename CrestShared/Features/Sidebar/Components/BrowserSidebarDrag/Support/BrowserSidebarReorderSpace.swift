import SwiftUI

/// Coordinate space for sidebar reordering.
///
/// Global rather than a named container: rows, folders, and space-picker
/// segments live in different branches of the sidebar hierarchy, and global
/// frames let one pointer location be compared against all of them without
/// every branch having to sit inside a shared container view.
enum BrowserSidebarReorderSpace {
    static var coordinateSpace: CoordinateSpace { .global }

    static var globalSpace: GlobalCoordinateSpace { .global }
}

/// Identifies the scroll viewport a reorder row or zone is rendered inside.
/// Fixed chrome leaves this unset, which is how the registry can clip only the
/// saved/current list geometry without clipping the pinned grid above it.
private struct BrowserSidebarScrollRegionIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var browserSidebarScrollRegionID: UUID? {
        get { self[BrowserSidebarScrollRegionIDKey.self] }
        set { self[BrowserSidebarScrollRegionIDKey.self] = newValue }
    }
}

/// The visible horizontal Space pager, independent of a page's vertical list.
private struct BrowserSidebarDropViewportIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var browserSidebarDropViewportID: UUID? {
        get { self[BrowserSidebarDropViewportIDKey.self] }
        set { self[BrowserSidebarDropViewportIDKey.self] = newValue }
    }

    /// The scroll content's own coordinate space, when the view lives inside a
    /// scrolling sidebar list whose origin is registered in global coordinates.
    /// Measuring rows and zones here avoids firing geometry updates on every
    /// scroll frame while keeping global coordinates exact for drags.
    @Entry var browserSidebarScrollContentSpace: NamedCoordinateSpace? = nil
}
