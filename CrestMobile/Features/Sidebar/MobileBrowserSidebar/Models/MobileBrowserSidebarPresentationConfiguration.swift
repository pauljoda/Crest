import SwiftUI

struct MobileBrowserSidebarPresentationConfiguration {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let dataDeleter: any BrowserSpaceDataDeleting
    let spaceAccess: BrowserSpaceAccessController
    let selectedColorScheme: ColorScheme
    let showsPasswords: Binding<Bool>
    let showsSettings: Binding<Bool>
    let presentedSpaceSheet: Binding<MobileBrowserSidebarSpaceSheet?>
    let clearHistoryConfirmation: Binding<BrowserSidebarClearHistoryConfirmation?>
    let utilitySearchText: Binding<String>
    let utilityFilter: Binding<BrowserUtilityListFilter>
    let utilityPresentation: BrowserUtilityPresentationState
    let selectedDownloadIDs: [UUID]
    let selectedSpaceAssignment: BrowserSpaceRuntimeAssignment?
    let clearHistoryConfirmationIsLive: Bool
    let selectTab: (TabID) -> Void
    let openURL: (URL) -> Void
    let acknowledgeDownloads: (BrowserUtilitySurface?) -> Void
}
