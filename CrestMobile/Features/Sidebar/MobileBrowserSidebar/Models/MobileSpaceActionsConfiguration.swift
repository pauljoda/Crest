import CoreGraphics

struct MobileSpaceActionsConfiguration {
    let showSettings: () -> Void
    let showArchive: () -> Void
    let showDownloads: () -> Void
    let commonListsAreExpanded: Bool
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void
    let togglePrivateBrowsing: () -> Void
}
