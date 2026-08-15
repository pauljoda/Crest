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
