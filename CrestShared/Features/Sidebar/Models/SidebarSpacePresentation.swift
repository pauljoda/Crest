import SwiftUI

/// The values a retained sidebar page draws from, independent of the session's
/// selected Space. This is presentation data, never authority for an action.
struct SidebarSpacePresentation: Equatable {
    let assignment: BrowserSpaceRuntimeAssignment
    let isUnlocked: Bool
    let tabIDs: Set<TabID>
    let folderIDs: Set<FolderID>
    let splitGroupIDs: Set<SplitGroupID>
    let branding: BrowserSpaceBranding
    let splitGroups: [BrowserSplitGroupMetadata]

    init(space: BrowserSpace, isUnlocked: Bool) {
        assignment = BrowserSpaceRuntimeAssignment(space: space)
        self.isUnlocked = isUnlocked
        tabIDs = Set(space.tabs.map(\.id))
        folderIDs = Set(space.folders.map(\.id))
        splitGroupIDs = Set(space.tabs.compactMap(\.splitGroupID))
        branding = space.branding
        splitGroups = space.splitGroups
    }

    func isAvailable(matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        self.assignment == assignment && isUnlocked
    }
}

/// A page's input role is separate from the values its rows draw. Shells that
/// omit the role already include live selection in their availability checks.
enum SidebarSpaceRole {
    static func permitsInteraction(isSelected: Bool?, isAvailable: Bool) -> Bool {
        isAvailable && isSelected != false
    }
}

extension EnvironmentValues {
    /// Shells without retained page roots keep their existing live reads.
    @Entry var sidebarSpacePresentation: SidebarSpacePresentation? = nil
    /// Read by interaction and editor-cleanup leaves, not row configurations.
    @Entry var sidebarSpaceIsSelected: Bool? = nil
}
