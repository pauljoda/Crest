import SwiftUI

struct SidebarTabRowInteractionContext {
    let isHovering: Binding<Bool>
    let isDropTargeted: Binding<Bool>
    let isRenaming: Bool
    let draftTitle: Binding<String>
    let isTitleFocused: FocusState<Bool>.Binding
    let beginRenaming: () -> Void
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void
    let dismissFromMiddleClick: () -> Void
}
