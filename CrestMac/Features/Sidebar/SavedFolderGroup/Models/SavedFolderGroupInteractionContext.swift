import SwiftUI

struct SavedFolderGroupInteractionContext {
    let isExpanded: Binding<Bool>
    let editingFolderRequest: Binding<BrowserFolderRuntimeAssignment?>
    let isDropTargeted: Binding<Bool>
    let draftTitle: Binding<String>
    let isChoosingColor: Binding<Bool>
    let isConfirmingDeletion: Binding<Bool>
    let collapsedTabVisibility: Binding<BrowserCollapsedFolderTabVisibilityState>
    let isTitleFocused: FocusState<Bool>.Binding
    let folderColor: Binding<BrowserSpaceBrandColor>
    let beginCreatingChild: () -> Void
    let beginRenaming: () -> Void
    let toggleExpansion: () -> Void
    let beginTitleEditingIfNeeded: () -> Void
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void
    let deleteFolder: () -> Void
    let unloadKeptCollapsedTab: (TabID) -> Void
}
